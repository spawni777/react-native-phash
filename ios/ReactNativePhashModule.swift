import ExpoModulesCore
import CocoaImageHashing
import Photos
import KDTree
import CryptoKit

let imageHashing = OSImageHashing.sharedInstance()

extension UIImage {
    func pixelData() -> [UInt8]? {
        let size = self.size
        let dataSize = size.width * size.height * 4
        var pixelData = [UInt8](repeating: 0, count: Int(dataSize))
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(data: &pixelData,
                                width: Int(size.width),
                                height: Int(size.height),
                                bitsPerComponent: 8,
                                bytesPerRow: 4 * Int(size.width),
                                space: colorSpace,
                                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        guard let cgImage = self.cgImage else { return nil }
        context?.draw(cgImage, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))

        return pixelData
    }
}

extension Data {
    func md5() -> String {
        let digest = Insecure.MD5.hash(data: self)
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }
}

struct FindSimilarOptions: Record {
  @Field
  var hashAlgorithmName: String

  @Field
  var storageIdentifier: String

  @Field
  var maxCacheSize: Int

  @Field
  var imageQuality: String

  @Field
  var maxHammingDistance: Int?

  @Field
  var nearestK: Int?

  @Field
  var concurrentBatchSize: Int?

  @Field
  var maxConcurrent: Int?
}

class ImageObject {
  var data: Data
  var appleId: String

  init(data: Data, appleId: String){
    self.data = data
    self.appleId = appleId
  }
}

class ImagePHashCache<DataType> {
    private var memoryCache = [String: DataType]()
    private let defaults = UserDefaults.standard
    private let maxCacheSize: Int
    private let storageIdentifier: String
    let isDisabled: Bool

    init(maxCacheSize: Int, storageIdentifier: String) {
        self.maxCacheSize = maxCacheSize
        self.storageIdentifier = storageIdentifier

        if maxCacheSize == 0 {
          self.isDisabled = true
          self.clearUserDefaults()
          return;
        }

        if let cacheDictionary = defaults.dictionary(forKey: storageIdentifier) as? [String: DataType] {
           self.memoryCache = cacheDictionary
        }

        self.isDisabled = false
    }

    func get(for key: String) -> DataType? {
        if isDisabled {
          return nil
        }

        guard let value = memoryCache[key] else {
          return nil
        }
        return value
    }

    func set(for key: String, value: DataType) {
        if (isDisabled) {
          return
        }

// 		if memoryCache[key] == value {
// 			return
// 		}
        memoryCache[key] = value
    }

    func clearUserDefaults() {
		defaults.removeObject(forKey: storageIdentifier)
    }

    func updateUserDefaults() {
        while memoryCache.count > maxCacheSize {
            let randomKey = memoryCache.keys.randomElement()!
            memoryCache.removeValue(forKey: randomKey)
        }

        defaults.set(memoryCache, forKey: storageIdentifier)
    }
}

struct Point64D: KDTreePoint {
    static var dimensions: Int { 64 }
    var coordinates: [Double]
    var appleId: String

    func kdDimension(_ dimension: Int) -> Double {
        return coordinates[dimension]
    }

    func squaredDistance(to otherPoint: Point64D) -> Double {
        let squaredDifferences = zip(coordinates, otherPoint.coordinates).map { (a, b) in (a - b) * (a - b) }
        let sumOfSquaredDifferences = squaredDifferences.reduce(0, +)
        return sqrt(sumOfSquaredDifferences)
    }
}

func calcHammingDistance(lhsData: [Double], rhsData: [Double]) -> Int {
  var diff = 0;

  for (i, _) in lhsData.enumerated() {
    if (lhsData[i] != rhsData[i]) {
      diff = diff + 1
    }
  }

  return diff;
}

func calcHammingDistance(lhsData: OSHashType, rhsData: OSHashType, hashAlgorithmName: String) -> OSHashDistanceType {
  switch hashAlgorithmName {
      case "dHash":
          return imageHashing.hashDistance(lhsData, to: rhsData, with: .dHash)
      case "pHash":
          return imageHashing.hashDistance(lhsData, to: rhsData, with: .pHash)
      default:
          return imageHashing.hashDistance(lhsData, to: rhsData, with: .aHash)
  }
}


public class ReactNativePhashModule: Module {
  // Each module class must implement the definition function. The definition consists of components
  // that describes the module's functionality and behavior.
  // See https://docs.expo.dev/modules/module-api for more details about available components.
  func calcPHashesStringConcurrently(imageAppleIds: [String], hashAlgorithmName: String, maxCacheSize: Int, storageIdentifier: String, concurrentBatchSize: Int, maxConcurrent: Int, imageQuality: String) -> [String?] {
    let cache = ImagePHashCache<String>(maxCacheSize: maxCacheSize, storageIdentifier: storageIdentifier)

    func calcPerceptualHash(imageData: Data, hashAlgorithmName: String) -> OSHashType {
        switch hashAlgorithmName {
            case "dHash":
                return imageHashing.hashImageData(imageData, with: .dHash)
            case "pHash":
                return imageHashing.hashImageData(imageData, with: .pHash)
            default:
                return imageHashing.hashImageData(imageData, with: .aHash)
        }
    }

    var pHashes: [(index: Int, hash: String?)] = []

    let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: imageAppleIds, options: nil)

    // Use DispatchGroup to keep track of the completion of all the image processing tasks
// 	let batchGroup = DispatchGroup()
    let pHashGroup = DispatchGroup()

    // Create a concurrent queue to perform the expensive task of calculating the perceptual hash of each image
    let queue = DispatchQueue(label: "spawni-phash-calculation", qos: .userInitiated, attributes: .concurrent)

	let semaphore = DispatchSemaphore(value: maxConcurrent)

    let totalImageCount = imageAppleIds.count
    var finishedImageCount = 0

    // batchCount rounded up
    let batchCount = (totalImageCount - 1 + concurrentBatchSize) / concurrentBatchSize

    self.sendEvent("pHash-calculated", [
        "finished": 0,
        "total": imageAppleIds.count
    ])
    for batchIndex in 0..<batchCount {
        // Wait for the semaphore to signal that it's safe to start a new task
        semaphore.wait()

        queue.async(group: pHashGroup) {
            autoreleasepool {
                let batchStartIndex = batchIndex * concurrentBatchSize
                let batchEndIndex = min((batchIndex + 1) * concurrentBatchSize, totalImageCount)
                let assets = fetchResult.objects(at: IndexSet(integersIn: batchStartIndex..<batchEndIndex))

                for (count, asset) in assets.enumerated() {
                     autoreleasepool {
                        // assuming you have a `PHAsset` instance called `asset`:
                        let options = PHImageRequestOptions()

						if imageQuality == "fastFormat" {
							options.deliveryMode = .fastFormat
						} else {
							options.deliveryMode = .highQualityFormat
						}
                        options.isSynchronous = true

                        var imageData: Data?

                        PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { (data, dataUTI, orientation, info) in
                            autoreleasepool {
                              imageData = data
                            }
                        }

                        guard let imageData = imageData else {
                            // handle error
                            // append the pHash and the index of the corresponding asset to the pHashes array
                            let tuple: (index: Int, hash: String?) = (index: batchStartIndex + count, hash: nil)
                            pHashes.append(tuple)

                            finishedImageCount = finishedImageCount + 1;
                            self.sendEvent("pHash-calculated", [
                                "finished": finishedImageCount,
                                "total": imageAppleIds.count
                            ])
                            return
                        }

                        var pHash: String

						if (!cache.isDisabled) {
                            let cacheKey = "\(asset.localIdentifier)_\(hashAlgorithmName)"
                            var cachedHash: String?

                            cachedHash = cache.get(for: cacheKey)

							if cachedHash != nil {
                                pHash = cachedHash!
                            } else {
                                let pHashRaw = calcPerceptualHash(imageData: imageData, hashAlgorithmName: hashAlgorithmName)
                                let pHashCropped = String(pHashRaw, radix: 2).replacingOccurrences(of: "-", with: "")
                                pHash = pHashCropped.padding(toLength: 64, withPad: "0", startingAt: 0)
                            }

                            queue.async(group: pHashGroup, flags:.barrier) {
                                cache.set(for: cacheKey, value: pHash)
                                // Signal the semaphore to indicate that the task is finished and a new task can start
                                semaphore.signal()
                            }
						} else {
							let pHashRaw = calcPerceptualHash(imageData: imageData, hashAlgorithmName: hashAlgorithmName)
                            let pHashCropped = String(pHashRaw, radix: 2).replacingOccurrences(of: "-", with: "")
                            pHash = pHashCropped.padding(toLength: 64, withPad: "0", startingAt: 0)
						}

                        // append the pHash and the index of the corresponding asset to the pHashes array
                        let tuple = (index: batchStartIndex + count, hash: pHash)

                        finishedImageCount = finishedImageCount + 1;
                        self.sendEvent("pHash-calculated", [
                            "finished": finishedImageCount,
                            "total": imageAppleIds.count
                        ])

                        queue.async(group: pHashGroup, flags:.barrier) {
                            pHashes.append(tuple)
                            // Signal the semaphore to indicate that the task is finished and a new task can start
                            semaphore.signal()
                        }
                     }
                }

                // Signal the semaphore to indicate that the task is finished and a new task can start
				semaphore.signal()
            }
        }
    }
    // Wait for all the image processing tasks to complete before returning the results
	pHashGroup.wait()

    // squeeze local cache to maxCacheSize elements
    cache.updateUserDefaults()

    // Sort the pHashes array by index to restore the original order
    pHashes.sort { $0.index < $1.index }

    // Return an array of pHash values without the index
    return pHashes.map { $0.hash }
  }

  func calcPHashesConcurrently(imageAppleIds: [String], hashAlgorithmName: String, maxCacheSize: Int, storageIdentifier: String, concurrentBatchSize: Int, maxConcurrent: Int, imageQuality: String) -> [OSHashType?] {
    let cache = ImagePHashCache<OSHashType>(maxCacheSize: maxCacheSize, storageIdentifier: storageIdentifier)

    func calcPerceptualHash(imageData: Data, hashAlgorithmName: String) -> OSHashType {
        switch hashAlgorithmName {
            case "dHash":
                return imageHashing.hashImageData(imageData, with: .dHash)
            case "pHash":
                return imageHashing.hashImageData(imageData, with: .pHash)
            default:
                return imageHashing.hashImageData(imageData, with: .aHash)
        }
    }

    var pHashes: [(index: Int, hash: OSHashType?)] = []

    let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: imageAppleIds, options: nil)

    // Use DispatchGroup to keep track of the completion of all the image processing tasks
    let pHashGroup = DispatchGroup()

    // Create a concurrent queue to perform the expensive task of calculating the perceptual hash of each image
    let queue = DispatchQueue(label: "spawni-phash-calculation", qos: .userInitiated, attributes: .concurrent)

    let semaphore = DispatchSemaphore(value: maxConcurrent)

    let totalImageCount = imageAppleIds.count
    var finishedImageCount = 0

    // batchCount rounded up
    let batchCount = (totalImageCount - 1 + concurrentBatchSize) / concurrentBatchSize

    self.sendEvent("pHash-calculated", [
        "finished": 0,
        "total": imageAppleIds.count
    ])
    for batchIndex in 0..<batchCount {
        // Wait for the semaphore to signal that it's safe to start a new task
        semaphore.wait()

        queue.async(group: pHashGroup) {
            autoreleasepool {
                let batchStartIndex = batchIndex * concurrentBatchSize
                let batchEndIndex = min((batchIndex + 1) * concurrentBatchSize, totalImageCount)
                let assets = fetchResult.objects(at: IndexSet(integersIn: batchStartIndex..<batchEndIndex))

                for (count, asset) in assets.enumerated() {
                     autoreleasepool {
                        // assuming you have a `PHAsset` instance called `asset`:
                        let options = PHImageRequestOptions()

                      if imageQuality == "fastFormat" {
                          options.deliveryMode = .fastFormat
                      } else {
                          options.deliveryMode = .highQualityFormat
                      }
                        options.isSynchronous = true

                        var imageData: Data?

                        PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { (data, dataUTI, orientation, info) in
                            autoreleasepool {
                              imageData = data
                            }
                        }

                        guard let imageData = imageData else {
                            // handle error
                            // append the pHash and the index of the corresponding asset to the pHashes array
                            let tuple: (index: Int, hash: OSHashType?) = (index: batchStartIndex + count, hash: nil)
                            pHashes.append(tuple)

                            finishedImageCount = finishedImageCount + 1;
                            self.sendEvent("pHash-calculated", [
                                "finished": finishedImageCount,
                                "total": imageAppleIds.count
                            ])
                            return
                        }

                        var pHash: OSHashType

                        if (!cache.isDisabled) {
                            let cacheKey = "\(asset.localIdentifier)_\(hashAlgorithmName)"
                            var cachedHash: OSHashType?

                            cachedHash = cache.get(for: cacheKey)

                          if cachedHash != nil {
                                pHash = cachedHash!
                          } else {
                              pHash = calcPerceptualHash(imageData: imageData, hashAlgorithmName: hashAlgorithmName)
                          }

                          queue.async(group: pHashGroup, flags:.barrier) {
                              cache.set(for: cacheKey, value: pHash)
                              // Signal the semaphore to indicate that the task is finished and a new task can start
                              semaphore.signal()
                          }
                        } else {
                            pHash = calcPerceptualHash(imageData: imageData, hashAlgorithmName: hashAlgorithmName)
                        }

                        // append the pHash and the index of the corresponding asset to the pHashes array
                        let tuple = (index: batchStartIndex + count, hash: pHash)

                        finishedImageCount = finishedImageCount + 1;
                        self.sendEvent("pHash-calculated", [
                            "finished": finishedImageCount,
                            "total": imageAppleIds.count
                        ])

                        queue.async(group: pHashGroup, flags:.barrier) {
                            pHashes.append(tuple)
                            // Signal the semaphore to indicate that the task is finished and a new task can start
                            semaphore.signal()
                        }
                     }
                }

                // Signal the semaphore to indicate that the task is finished and a new task can start
              semaphore.signal()
            }
        }
    }
    // Wait for all the image processing tasks to complete before returning the results
    pHashGroup.wait()

    // squeeze local cache to maxCacheSize elements
    cache.updateUserDefaults()

    // Sort the pHashes array by index to restore the original order
    pHashes.sort { $0.index < $1.index }

    // Return an array of pHash values without the index
    return pHashes.map { $0.hash }
  }

  func calcPHashesConcurrently2(imageAppleIds: [String], hashAlgorithmName: String, maxCacheSize: Int, storageIdentifier: String, concurrentBatchSize: Int, maxConcurrent: Int, imageQuality: String) -> [OSHashType?] {
    let cache = ImagePHashCache<OSHashType>(maxCacheSize: maxCacheSize, storageIdentifier: storageIdentifier)

    func calcPerceptualHash(imageData: Data, hashAlgorithmName: String) -> OSHashType {
        switch hashAlgorithmName {
            case "dHash":
                return imageHashing.hashImageData(imageData, with: .dHash)
            case "pHash":
                return imageHashing.hashImageData(imageData, with: .pHash)
            default:
                return imageHashing.hashImageData(imageData, with: .aHash)
        }
    }

    var pHashes: [(index: Int, hash: OSHashType?)] = []

    let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: imageAppleIds, options: nil)

    // Use DispatchGroup to keep track of the completion of all the image processing tasks
    let pHashGroup = DispatchGroup()

    // Create a concurrent queue to perform the expensive task of calculating the perceptual hash of each image
    let queue = DispatchQueue(label: "spawni-phash-calculation", qos: .userInitiated, attributes: .concurrent)

    let semaphore = DispatchSemaphore(value: maxConcurrent)

    let totalImageCount = imageAppleIds.count
    var finishedImageCount = 0

    // batchCount rounded up
    let batchCount = (totalImageCount - 1 + concurrentBatchSize) / concurrentBatchSize

    self.sendEvent("pHash-calculated", [
        "finished": 0,
        "total": imageAppleIds.count
    ])
    for batchIndex in 0..<batchCount {
        // Wait for the semaphore to signal that it's safe to start a new task
        semaphore.wait()

        queue.async(group: pHashGroup) {
            autoreleasepool {
                let batchStartIndex = batchIndex * concurrentBatchSize
                let batchEndIndex = min((batchIndex + 1) * concurrentBatchSize, totalImageCount)
                let assets = fetchResult.objects(at: IndexSet(integersIn: batchStartIndex..<batchEndIndex))

                for (count, asset) in assets.enumerated() {
                     autoreleasepool {
                        // assuming you have a `PHAsset` instance called `asset`:
                        let options = PHImageRequestOptions()

                        if imageQuality == "fastFormat" {
                            options.deliveryMode = .fastFormat
                        } else {
                            options.deliveryMode = .highQualityFormat
                        }
                        options.isSynchronous = true

                        var imageData: Data?

                        PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: 64, height: 64), contentMode: .aspectFill, options: options) { (image, info) in
                            autoreleasepool {
                              guard let image: UIImage = image else {
                                return
                              }

                              let data = image.pngData()
                              if (data == nil) {
                                return
                              }

                              imageData = data
                            }
                        }

                        guard let imageData = imageData else {
                            // handle error
                            // append the pHash and the index of the corresponding asset to the pHashes array
                            let tuple: (index: Int, hash: OSHashType?) = (index: batchStartIndex + count, hash: nil)
                            pHashes.append(tuple)

                            finishedImageCount = finishedImageCount + 1;
                            self.sendEvent("pHash-calculated", [
                                "finished": finishedImageCount,
                                "total": imageAppleIds.count
                            ])
                            return
                        }

                        var pHash: OSHashType

                        if (!cache.isDisabled) {
                            let cacheKey = "\(asset.localIdentifier)_\(hashAlgorithmName)"
                            var cachedHash: OSHashType?

                            cachedHash = cache.get(for: cacheKey)

                          if cachedHash != nil {
                                pHash = cachedHash!
                          } else {
                              pHash = calcPerceptualHash(imageData: imageData, hashAlgorithmName: hashAlgorithmName)
                          }

                          queue.async(group: pHashGroup, flags:.barrier) {
                              cache.set(for: cacheKey, value: pHash)
                              // Signal the semaphore to indicate that the task is finished and a new task can start
                              semaphore.signal()
                          }
                        } else {
                            pHash = calcPerceptualHash(imageData: imageData, hashAlgorithmName: hashAlgorithmName)
                        }

                        // append the pHash and the index of the corresponding asset to the pHashes array
                        let tuple = (index: batchStartIndex + count, hash: pHash)

                        finishedImageCount = finishedImageCount + 1;
                        self.sendEvent("pHash-calculated", [
                            "finished": finishedImageCount,
                            "total": imageAppleIds.count
                        ])

                        queue.async(group: pHashGroup, flags:.barrier) {
                            pHashes.append(tuple)
                            // Signal the semaphore to indicate that the task is finished and a new task can start
                            semaphore.signal()
                        }
                     }
                }

                // Signal the semaphore to indicate that the task is finished and a new task can start
              semaphore.signal()
            }
        }
    }
    // Wait for all the image processing tasks to complete before returning the results
    pHashGroup.wait()

    // squeeze local cache to maxCacheSize elements
    cache.updateUserDefaults()

    // Sort the pHashes array by index to restore the original order
    pHashes.sort { $0.index < $1.index }

    // Return an array of pHash values without the index
    return pHashes.map { $0.hash }
  }

  func calcPHashesStringIterative(imageAppleIds: [String], hashAlgorithmName: String, maxCacheSize: Int, storageIdentifier: String, imageQuality: String) -> [String?] {
      let cache = ImagePHashCache<String>(maxCacheSize: maxCacheSize, storageIdentifier: storageIdentifier)

      func calcPerceptualHash(imageData: Data, hashAlgorithmName: String) -> OSHashType {
          switch hashAlgorithmName {
              case "dHash":
                  return imageHashing.hashImageData(imageData, with: .dHash)
              case "pHash":
                  return imageHashing.hashImageData(imageData, with: .pHash)
              default:
                  return imageHashing.hashImageData(imageData, with: .aHash)
          }
      }

      var pHashes = [String?]()

      let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: imageAppleIds, options: nil)
      var finishedImageCount = 0

      self.sendEvent("pHash-calculated", [
          "finished": 0,
          "total": imageAppleIds.count
      ])

      fetchResult.enumerateObjects{  (asset, count, stop) in
          autoreleasepool {
              // assuming you have a `PHAsset` instance called `asset`:
              let options = PHImageRequestOptions()

	          if imageQuality == "fastFormat" {
		          options.deliveryMode = .fastFormat
	          } else {
		          options.deliveryMode = .highQualityFormat
	          }
              options.isSynchronous = true

              var imageData: Data?

              PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { (data, dataUTI, orientation, info) in
                  autoreleasepool {
                    imageData = data
                  }
              }

              guard let imageData = imageData else {
                  // handle error
                  pHashes.append(nil)

                  finishedImageCount = finishedImageCount + 1;
                  self.sendEvent("pHash-calculated", [
                      "finished": finishedImageCount,
                      "total": imageAppleIds.count
                  ])
                  return
              }

              let cacheKey = "\(asset.localIdentifier)_\(hashAlgorithmName)"
              var pHash: String

              if let cachedHash = cache.get(for: cacheKey) {
                  pHash = cachedHash
              } else {
                  let pHashRaw = calcPerceptualHash(imageData: imageData, hashAlgorithmName: hashAlgorithmName)
                  let pHashCropped = String(pHashRaw, radix: 2).replacingOccurrences(of: "-", with: "")
                  pHash = pHashCropped.padding(toLength: 64, withPad: "0", startingAt: 0)
                  cache.set(for: cacheKey, value: pHash)
              }

              // append the pHash and the index of the corresponding asset to the pHashes array
              pHashes.append(pHash)

              finishedImageCount = finishedImageCount + 1;
              self.sendEvent("pHash-calculated", [
                  "finished": finishedImageCount,
                  "total": imageAppleIds.count
              ])
          }
      }

      // squeeze local cache to maxCacheSize elements
      cache.updateUserDefaults()

      // Return an array of pHash values without the index
      return pHashes
  }

  func calcPHashesIterative(imageAppleIds: [String], hashAlgorithmName: String, maxCacheSize: Int, storageIdentifier: String, imageQuality: String) -> [OSHashType?] {
      let cache = ImagePHashCache<OSHashType>(maxCacheSize: maxCacheSize, storageIdentifier: storageIdentifier)

      func calcPerceptualHash(imageData: Data, hashAlgorithmName: String) -> OSHashType {
          switch hashAlgorithmName {
              case "dHash":
                  return imageHashing.hashImageData(imageData, with: .dHash)
              case "pHash":
                  return imageHashing.hashImageData(imageData, with: .pHash)
              default:
                  return imageHashing.hashImageData(imageData, with: .aHash)
          }
      }

      var pHashes = [OSHashType?]()

      let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: imageAppleIds, options: nil)
      var finishedImageCount = 0

      self.sendEvent("pHash-calculated", [
          "finished": 0,
          "total": imageAppleIds.count
      ])

      fetchResult.enumerateObjects{  (asset, count, stop) in
          autoreleasepool {
              // assuming you have a `PHAsset` instance called `asset`:
              let options = PHImageRequestOptions()

              if imageQuality == "fastFormat" {
                  options.deliveryMode = .fastFormat
              } else {
                  options.deliveryMode = .highQualityFormat
              }
              options.isSynchronous = true

              var imageData: Data?

              PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { (data, dataUTI, orientation, info) in
                  autoreleasepool {
                    imageData = data
                  }
              }

              guard let imageData = imageData else {
                  // handle error
                  pHashes.append(nil)

                  finishedImageCount = finishedImageCount + 1;
                  self.sendEvent("pHash-calculated", [
                      "finished": finishedImageCount,
                      "total": imageAppleIds.count
                  ])
                  return
              }

              let cacheKey = "\(asset.localIdentifier)_\(hashAlgorithmName)"
              var pHash: OSHashType

              if let cachedHash = cache.get(for: cacheKey) {
                  pHash = cachedHash
              } else {
                  pHash = calcPerceptualHash(imageData: imageData, hashAlgorithmName: hashAlgorithmName)
                  cache.set(for: cacheKey, value: pHash)
              }

              // append the pHash and the index of the corresponding asset to the pHashes array
              pHashes.append(pHash)

              finishedImageCount = finishedImageCount + 1;
              self.sendEvent("pHash-calculated", [
                  "finished": finishedImageCount,
                  "total": imageAppleIds.count
              ])
          }
      }

      // squeeze local cache to maxCacheSize elements
      cache.updateUserDefaults()

      // Return an array of pHash values without the index
      return pHashes
  }

  func findDuplicatesIterative(imageAppleIds: [String], maxCacheSize: Int, storageIdentifier: String) -> [[String]] {
    let cache = ImagePHashCache<String>(maxCacheSize: maxCacheSize, storageIdentifier: storageIdentifier)

    var duplicates = [[String]]()

    let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: imageAppleIds, options: nil)
    var finishedImageCount = 0

    self.sendEvent("md5-calculated", [
        "finished": 0,
        "total": imageAppleIds.count
    ])

	var imageHashesMap = [String: [String]]()

    fetchResult.enumerateObjects{  (asset, count, stop) in
        autoreleasepool {
            // assuming you have a `PHAsset` instance called `asset`:
            var imageData: Data?

            let options = PHImageRequestOptions()

            options.isSynchronous = true

            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { (data, dataUTI, orientation, info) in
                autoreleasepool {
                  imageData = data
                }
            }

            guard let imageData = imageData else {
                // handle error
                finishedImageCount = finishedImageCount + 1;
                self.sendEvent("md5-calculated", [
                    "finished": finishedImageCount,
                    "total": imageAppleIds.count
                ])
                return
            }

            let cacheKey = "\(asset.localIdentifier)_md5"
            var hash: String

            if let cachedHash = cache.get(for: cacheKey) {
                hash = cachedHash
            } else {
                hash = imageData.md5()
                cache.set(for: cacheKey, value: hash)
            }

            if (imageHashesMap[hash] == nil) {
              imageHashesMap[hash] = [imageAppleIds[count]]
            } else {
              var appleIds = imageHashesMap[hash]!

              appleIds.append(imageAppleIds[count])
              imageHashesMap[hash] = appleIds
            }

            finishedImageCount = finishedImageCount + 1;
            self.sendEvent("md5-calculated", [
                "finished": finishedImageCount,
                "total": imageAppleIds.count
            ])
        }
    }

    // squeeze local cache to maxCacheSize elements
    cache.updateUserDefaults()

	var hashes = [[String]]()

	for (hash, appleIds) in imageHashesMap {
		if (appleIds.count > 1) {
			hashes.append(appleIds);
		}
    }

    // Return an array of pHash values without the index
    return hashes
  }

  public func definition() -> ModuleDefinition {
    // Sets the name of the module that JavaScript code will use to refer to the module. Takes a string as an argument.
    // Can be inferred from module's class name, but it's recommended to set it explicitly for clarity.
    // The module will be accessible from `requireNativeModule('ReactNativePhash')` in JavaScript.
    Name("ReactNativePhash")

    Events("pHash-calculated", "md5-calculated")

    // Defines a JavaScript function that always returns a Promise and whose native code
    // is by default dispatched on the different thread than the JavaScript runtime runs on.
    AsyncFunction("getPHashesIterative") { (imageAppleIds: [String], options: FindSimilarOptions) -> [String?] in
        let pHashes = calcPHashesStringIterative(
          imageAppleIds: imageAppleIds,
          hashAlgorithmName: options.hashAlgorithmName,
          maxCacheSize: options.maxCacheSize,
          storageIdentifier: options.storageIdentifier,
          imageQuality: options.imageQuality
        )
        return pHashes
    }

    AsyncFunction("getPHashesConcurrently") { (imageAppleIds: [String], options: FindSimilarOptions) -> [String?] in
        let pHashes = calcPHashesStringConcurrently(
          imageAppleIds: imageAppleIds,
          hashAlgorithmName: options.hashAlgorithmName,
          maxCacheSize: options.maxCacheSize,
          storageIdentifier: options.storageIdentifier,
          concurrentBatchSize: options.concurrentBatchSize!,
          maxConcurrent: options.maxConcurrent!,
          imageQuality: options.imageQuality
        );
        return pHashes
    }

    AsyncFunction("findDuplicatesIterative") { (imageAppleIds: [String], options: FindSimilarOptions) -> [[String]] in
        let duplicates = findDuplicatesIterative(
          imageAppleIds: imageAppleIds,
          maxCacheSize: options.maxCacheSize,
          storageIdentifier: options.storageIdentifier
        )
        return duplicates
    }

    AsyncFunction("findSimilarIterativeOld") { (imageAppleIds: [String], options: FindSimilarOptions) -> [[String]] in
	    let pHashes = calcPHashesStringIterative(
          imageAppleIds: imageAppleIds,
          hashAlgorithmName: options.hashAlgorithmName,
          maxCacheSize: options.maxCacheSize,
          storageIdentifier: options.storageIdentifier,
          imageQuality: options.imageQuality
        )

        let maxHammingDistance = options.maxHammingDistance!
        let hashAlgorithmName = options.hashAlgorithmName
		let nearestK = options.nearestK!

        var similarImages = [[String]]()
        var similarImagesMap = [String: Bool]()

        for i in 0..<pHashes.count - 1 {
            if (similarImagesMap[imageAppleIds[i]] != nil) {
              continue
            }

            guard let pHash1 = pHashes[i] else {
                continue
            }

            var collisions: [String] = [imageAppleIds[i]]

            for j in (i + 1)..<pHashes.count {
                if (collisions.count >= nearestK) {
                  break
                }

                if (similarImagesMap[imageAppleIds[j]] != nil) {
                  continue
                }

                if (imageAppleIds[i] == imageAppleIds[j]) {
                  continue
                }

                guard let pHash2 = pHashes[j], i < j else {
                    continue
                }

                let pHashDoubleArray1 = pHash1.map {Double(String($0)) ?? 0}
                let pHashDoubleArray2 = pHash2.map {Double(String($0)) ?? 0}
                let hammingDistance = calcHammingDistance(lhsData: pHashDoubleArray1, rhsData: pHashDoubleArray2)

                if hammingDistance <= maxHammingDistance {
                    collisions.append(imageAppleIds[j])
                }
            }

            if (collisions.count >= 2) {
                similarImages.append(collisions)

                for collision in collisions {
                  similarImagesMap[collision] = true
                }
            }
        }

        return similarImages
    }

    AsyncFunction("findSimilarIterativeKDTree") { (imageAppleIds: [String], options: FindSimilarOptions) -> [[String]] in
        let pHashes = calcPHashesStringIterative(
          imageAppleIds: imageAppleIds,
          hashAlgorithmName: options.hashAlgorithmName,
          maxCacheSize: options.maxCacheSize,
          storageIdentifier: options.storageIdentifier,
          imageQuality: options.imageQuality
        )

		let maxHammingDistance = options.maxHammingDistance!
		let nearestK = options.nearestK!

        var points64D = [Point64D]()

        for (index, pHash) in pHashes.enumerated() {
            if (pHash == nil) {
              continue
            }
            let binaryStringArray: [String] = pHash!.map { String($0) }
            let doubleArray = binaryStringArray.map { Double($0) ?? 0 }

            points64D.append(Point64D(coordinates: doubleArray, appleId: imageAppleIds[index]))
        }

        let kdTree: KDTree<Point64D> = KDTree(values: points64D)
        var similarImages = [[String]]()
        var foundSimilarityIdsHashMap = [String: Int]()

        for (pointIndex, point) in points64D.enumerated() {
            if foundSimilarityIdsHashMap[point.appleId] != nil {
                continue
            }
            foundSimilarityIdsHashMap[point.appleId] = 1;

            autoreleasepool {
                let nearestPoints: [Point64D] = kdTree.nearestK(nearestK, to: point)
                var collisions: [String] = [point.appleId]

                for neighbor in nearestPoints {
                  if foundSimilarityIdsHashMap[neighbor.appleId] != nil {
                      continue
                  }

                  let hammingDistance = calcHammingDistance(lhsData: neighbor.coordinates, rhsData: point.coordinates)

                  if (hammingDistance > maxHammingDistance) {
                    continue
                  }

                  foundSimilarityIdsHashMap[neighbor.appleId] = 1
                  collisions.append(neighbor.appleId)
                }

                if (collisions.count >= 2) {
                  similarImages.append(collisions)
                }
            }
        }

        return similarImages
    }

    AsyncFunction("findSimilarConcurrentlyPartial") { (imageAppleIds: [String], options: FindSimilarOptions) -> [[String]] in
        let pHashes = calcPHashesStringConcurrently(
          imageAppleIds: imageAppleIds,
          hashAlgorithmName: options.hashAlgorithmName,
          maxCacheSize: options.maxCacheSize,
          storageIdentifier: options.storageIdentifier,
          concurrentBatchSize: options.concurrentBatchSize!,
          maxConcurrent: options.maxConcurrent!,
          imageQuality: options.imageQuality
        );
        let maxHammingDistance = options.maxHammingDistance!
        let nearestK = options.nearestK!

        var points64D = [Point64D]()

        for (index, pHash) in pHashes.enumerated() {
          if (pHash == nil) {
            continue
          }
          let binaryStringArray: [String] = pHash!.map { String($0) }
          let doubleArray = binaryStringArray.map { Double($0) ?? 0 }

          points64D.append(Point64D(coordinates: doubleArray, appleId: imageAppleIds[index]))
        }

        let kdTree: KDTree<Point64D> = KDTree(values: points64D)
        var similarImages = [[String]]()
        var foundSimilarityIdsHashMap = [String: Int]()

        for (pointIndex, point) in points64D.enumerated() {
          if foundSimilarityIdsHashMap[point.appleId] != nil {
              continue
          }
          foundSimilarityIdsHashMap[point.appleId] = 1;

          let nearestPoints: [Point64D] = kdTree.nearestK(nearestK, to: point)
          var collisions: [String] = [point.appleId]

          for neighbor in nearestPoints {
            if foundSimilarityIdsHashMap[neighbor.appleId] != nil {
                continue
            }

            let hammingDistance = calcHammingDistance(lhsData: neighbor.coordinates, rhsData: point.coordinates)

            if (hammingDistance > maxHammingDistance) {
              continue
            }

            foundSimilarityIdsHashMap[neighbor.appleId] = 1
            collisions.append(neighbor.appleId)
          }

          if (collisions.count >= 2) {
            similarImages.append(collisions)
          }
        }

        return similarImages
    }

    AsyncFunction("findSimilarConcurrentlyOld") { (imageAppleIds: [String], options: FindSimilarOptions) -> [[String]] in
        let concurrentBatchSize = options.concurrentBatchSize!
        let maxHammingDistance = options.maxHammingDistance!
        let maxConcurrent = options.maxConcurrent!
        let nearestK = options.nearestK!

        let pHashes = calcPHashesStringConcurrently(
          imageAppleIds: imageAppleIds,
          hashAlgorithmName: options.hashAlgorithmName,
          maxCacheSize: options.maxCacheSize,
          storageIdentifier: options.storageIdentifier,
          concurrentBatchSize: concurrentBatchSize,
          maxConcurrent: maxConcurrent,
          imageQuality: options.imageQuality
        );

        var points64D = [Point64D]()

        for (index, pHash) in pHashes.enumerated() {
          if (pHash == nil) {
            continue
          }
          let binaryStringArray: [String] = pHash!.map { String($0) }
          let doubleArray = binaryStringArray.map { Double($0) ?? 0 }

          points64D.append(Point64D(coordinates: doubleArray, appleId: imageAppleIds[index]))
        }

        let kdTree: KDTree<Point64D> = KDTree(values: points64D)

	    // Use DispatchGroup to keep track of the completion of all the image processing tasks
        let group = DispatchGroup()

        // Create a concurrent queue to perform the expensive task of calculating the perceptual hash of each image
        let queue = DispatchQueue(label: "spawni-phash-calculation", qos: .userInitiated, attributes: .concurrent)
        let semaphore = DispatchSemaphore(value: maxConcurrent)

		let totalImageCount = imageAppleIds.count
        // batchCount rounded up
        let batchCount = (totalImageCount - 1 + concurrentBatchSize) / concurrentBatchSize

        var similarImages = [[String]]()
        var finishedImageCount = 0;

        for batchIndex in 0..<batchCount {
            semaphore.wait()

            queue.async(group: group) {
                autoreleasepool {
                    // Wait for the semaphore to signal that it's safe to start a new task

                    let batchStartIndex = batchIndex * concurrentBatchSize
                    let batchEndIndex = min((batchIndex + 1) * concurrentBatchSize, totalImageCount)
                    let batchPoints = Array(points64D[batchStartIndex..<batchEndIndex])

                    for (pointIndex, point) in batchPoints.enumerated() {
                        autoreleasepool {
                            let nearestPoints: [Point64D] = kdTree.nearestK(nearestK, to: point)
                            var collisions: [String] = [point.appleId]

                            for neighbor in nearestPoints {
                                if (neighbor.appleId == point.appleId) {
                                  continue
                                }

                                let hammingDistance = calcHammingDistance(lhsData: neighbor.coordinates, rhsData: point.coordinates)

                                if (hammingDistance > maxHammingDistance) {
                                  continue
                                }

                                collisions.append(neighbor.appleId)
                            }

                            if (collisions.count >= 2) {
                                queue.async(group: group, flags:.barrier) {
                                    similarImages.append(collisions)
                                    semaphore.signal()
                                }
                            }
							// WARNING. REMOVE THIS IF CRUSH?!?!?!?
                            finishedImageCount = finishedImageCount + 1;
                        }
                    }

                    // Signal the semaphore to indicate that the task is finished and a new task can start
                    semaphore.signal()
                }
            }
        }

        // Wait for all the image processing tasks to complete before returning the results
        group.wait()

        var foundSimilarityIdsHashMap = [String: Int]()
        var refactoredSimilarImages = [[String]]()

        for collisions in similarImages {
          var repeated = false

          for pointId in collisions {
            if foundSimilarityIdsHashMap[pointId] != nil {
              repeated = true
              break
            }
            foundSimilarityIdsHashMap[pointId] = 1
          }

          if repeated {
            continue
          }

          refactoredSimilarImages.append(collisions)
        }

        return refactoredSimilarImages
    }

    AsyncFunction("findSimilarConcurrently") { (imageAppleIds: [String], options: FindSimilarOptions) -> [[String]] in
        let pHashes = calcPHashesConcurrently(
          imageAppleIds: imageAppleIds,
          hashAlgorithmName: options.hashAlgorithmName,
          maxCacheSize: options.maxCacheSize,
          storageIdentifier: options.storageIdentifier,
          concurrentBatchSize: options.concurrentBatchSize!,
          maxConcurrent: options.maxConcurrent!,
          imageQuality: options.imageQuality
        );

        let maxHammingDistance = options.maxHammingDistance!
		let nearestK = options.nearestK!
		let hashAlgorithmName = options.hashAlgorithmName
        var similarImages = [[String]]()
		var similarImagesMap = [String: Bool]()

        for i in 0..<pHashes.count - 1 {
            if (similarImagesMap[imageAppleIds[i]] != nil) {
              continue
            }

            guard let pHash1 = pHashes[i] else {
                continue
            }

            var collisions: [String] = [imageAppleIds[i]]

            for j in (i + 1)..<pHashes.count {
                if (collisions.count > nearestK) {
                  break
                }

                if (similarImagesMap[imageAppleIds[j]] != nil) {
                  continue
                }

                if (imageAppleIds[i] == imageAppleIds[j]) {
                  continue
                }

                guard let pHash2 = pHashes[j], i < j else {
                    continue
                }

                let hammingDistance = calcHammingDistance(lhsData: pHash1, rhsData: pHash2, hashAlgorithmName: hashAlgorithmName)

                if hammingDistance <= maxHammingDistance {
                    collisions.append(imageAppleIds[j])
                }
            }

            if (collisions.count >= 2) {
                similarImages.append(collisions)

                for collision in collisions {
                  similarImagesMap[collision] = true
                }
            }
        }

        return similarImages
    }

    AsyncFunction("findSimilarConcurrently2") { (imageAppleIds: [String], options: FindSimilarOptions) -> [[String]] in
        let pHashes = calcPHashesConcurrently2(
          imageAppleIds: imageAppleIds,
          hashAlgorithmName: options.hashAlgorithmName,
          maxCacheSize: options.maxCacheSize,
          storageIdentifier: options.storageIdentifier,
          concurrentBatchSize: options.concurrentBatchSize!,
          maxConcurrent: options.maxConcurrent!,
          imageQuality: options.imageQuality
        );

        let maxHammingDistance = options.maxHammingDistance!
        let nearestK = options.nearestK!
        let hashAlgorithmName = options.hashAlgorithmName
        var similarImages = [[String]]()
        var similarImagesMap = [String: Bool]()

        for i in 0..<pHashes.count - 1 {
            if (similarImagesMap[imageAppleIds[i]] != nil) {
              continue
            }

            guard let pHash1 = pHashes[i] else {
                continue
            }

            var collisions: [String] = [imageAppleIds[i]]

            for j in (i + 1)..<pHashes.count {
                if (collisions.count > nearestK) {
                  break
                }

                if (similarImagesMap[imageAppleIds[j]] != nil) {
                  continue
                }

                if (imageAppleIds[i] == imageAppleIds[j]) {
                  continue
                }

                guard let pHash2 = pHashes[j], i < j else {
                    continue
                }

                let hammingDistance = calcHammingDistance(lhsData: pHash1, rhsData: pHash2, hashAlgorithmName: hashAlgorithmName)

                if hammingDistance <= maxHammingDistance {
                    collisions.append(imageAppleIds[j])
                }
            }

            if (collisions.count >= 2) {
                similarImages.append(collisions)

                for collision in collisions {
                  similarImagesMap[collision] = true
                }
            }
        }

        return similarImages
    }

    AsyncFunction("findSimilarIterative") { (imageAppleIds: [String], options: FindSimilarOptions) -> [[String]] in
        let pHashes = calcPHashesIterative(
          imageAppleIds: imageAppleIds,
          hashAlgorithmName: options.hashAlgorithmName,
          maxCacheSize: options.maxCacheSize,
          storageIdentifier: options.storageIdentifier,
          imageQuality: options.imageQuality
        )

        let maxHammingDistance = options.maxHammingDistance!
		let nearestK = options.nearestK!
		let hashAlgorithmName = options.hashAlgorithmName

        var similarImages = [[String]]()
        var similarImagesMap = [String: Bool]()

        for i in 0..<pHashes.count - 1 {
            if (similarImagesMap[imageAppleIds[i]] != nil) {
              continue
            }

            guard let pHash1 = pHashes[i] else {
                continue
            }

            var collisions: [String] = [imageAppleIds[i]]

            for j in (i + 1)..<pHashes.count {
                if (collisions.count >= nearestK) {
                  break
                }

                if (similarImagesMap[imageAppleIds[j]] != nil) {
                  continue
                }

                if (imageAppleIds[i] == imageAppleIds[j]) {
                  continue
                }

                guard let pHash2 = pHashes[j], i < j else {
                    continue
                }

                let hammingDistance = calcHammingDistance(lhsData: pHash1, rhsData: pHash2, hashAlgorithmName: hashAlgorithmName)

                if hammingDistance <= maxHammingDistance {
                    collisions.append(imageAppleIds[j])
                }
            }

            if (collisions.count >= 2) {
                similarImages.append(collisions)

                for collision in collisions {
                  similarImagesMap[collision] = true
                }
            }
        }

        return similarImages
    }
  }
}
