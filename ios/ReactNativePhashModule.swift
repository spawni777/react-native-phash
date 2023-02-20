import ExpoModulesCore
import CocoaImageHashing
import Photos
import KDTree

let imageHashing = OSImageHashing.sharedInstance()

class ImageObject {
  var data: Data
  var appleId: String

  init(data: Data, appleId: String){
    self.data = data
    self.appleId = appleId
  }
}

class ImagePHashCache {
    private var memoryCache = [String:String]()
    private let defaults = UserDefaults.standard
    private let maxCacheSize: Int
    private let storageIdentifier: String
    let isDisabled: Bool

    init(maxCacheSize: Int, storageIdentifier: String) {
        self.maxCacheSize = maxCacheSize
        self.storageIdentifier = storageIdentifier

        if maxCacheSize == 0 {
          self.isDisabled = true
          self.clear()
          return;
        }

        if let cacheDictionary = defaults.dictionary(forKey: storageIdentifier) as? [String: String] {
           self.memoryCache = cacheDictionary
        }

        self.isDisabled = false
    }

    func get(for key: String) -> String? {
        if isDisabled {
          return nil
        }

        guard let value = memoryCache[key] else {
          return nil
        }
        return value
    }

    func set(for key: String, value: String) {
        if (isDisabled) {
          return
        }

        memoryCache[key] = value

        if memoryCache.count > maxCacheSize {
            let randomKey = memoryCache.keys.randomElement()!
            memoryCache.removeValue(forKey: randomKey)
        }

        defaults.set(memoryCache, forKey: storageIdentifier)
    }

    func delete(for key: String) {
        memoryCache.removeValue(forKey: key)

        defaults.set(memoryCache, forKey: storageIdentifier)
    }

    func clear() {
      let defaults = UserDefaults.standard
      let dictionary = defaults.dictionaryRepresentation()

      dictionary.keys.forEach { key in
          defaults.removeObject(forKey: key)
      }
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


public class ReactNativePhashModule: Module {
  // Each module class must implement the definition function. The definition consists of components
  // that describes the module's functionality and behavior.
  // See https://docs.expo.dev/modules/module-api for more details about available components.
  func calcPerceptualHashes(imageAppleIds: [String], hashAlgorithmName: String, maxCacheSize: Int, storageIdentifier: String, concurrentBatchSize: Int, maxConcurrent: Int) -> [String?] {
    let cache = ImagePHashCache(maxCacheSize: maxCacheSize, storageIdentifier: storageIdentifier)

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
    let batchGroup = DispatchGroup()

    // Create a concurrent queue to perform the expensive task of calculating the perceptual hash of each image
    let queue = DispatchQueue(label: storageIdentifier, qos: .userInitiated, attributes: .concurrent)

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

        queue.async(group: batchGroup) {
            batchGroup.enter()

            // Wait for the semaphore to signal that it's safe to start a new task
            semaphore.wait()

            let batchStartIndex = batchIndex * concurrentBatchSize
            let batchEndIndex = min((batchIndex + 1) * concurrentBatchSize, totalImageCount)
            let assets = fetchResult.objects(at: IndexSet(integersIn: batchStartIndex..<batchEndIndex))

            for (count, asset) in assets.enumerated() {
                // assuming you have a `PHAsset` instance called `asset`:
                let options = PHImageRequestOptions()
                options.deliveryMode = .fastFormat
                options.isSynchronous = true
                PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { (imageData, dataUTI, orientation, info) in
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
                    let tuple = (index: batchStartIndex + count, hash: pHash)
                    pHashes.append(tuple)

                    finishedImageCount = finishedImageCount + 1;
                    self.sendEvent("pHash-calculated", [
                        "finished": finishedImageCount,
                        "total": imageAppleIds.count
                    ])
                }
            }

            batchGroup.leave()
            // Signal the semaphore to indicate that the task is finished and a new task can start
            semaphore.signal()
        }
    }
    // Wait for all the image processing tasks to complete before returning the results
    batchGroup.wait()

    let expectedIndexes = Set(0..<totalImageCount)
    let presentIndexes = Set(pHashes.map { $0.index })
    let missingIndexes = expectedIndexes.subtracting(presentIndexes)

    // Append nil for missing indexes
    for index in missingIndexes {
        let tuple: (index: Int, hash: String?) = (index: index, hash: nil)
        pHashes.append(tuple)
    }

    // Sort the pHashes array by index to restore the original order
    pHashes.sort { $0.index < $1.index }

    // Return an array of pHash values without the index
    return pHashes.map { $0.hash }
  }

  public func definition() -> ModuleDefinition {
    // Sets the name of the module that JavaScript code will use to refer to the module. Takes a string as an argument.
    // Can be inferred from module's class name, but it's recommended to set it explicitly for clarity.
    // The module will be accessible from `requireNativeModule('ReactNativePhash')` in JavaScript.
    Name("ReactNativePhash")

    Events("pHash-calculated", "find-similar-iteration")

    // Defines a JavaScript function that always returns a Promise and whose native code
    // is by default dispatched on the different thread than the JavaScript runtime runs on.
    AsyncFunction("getPerceptualHashes") { (imageAppleIds: [String], hashAlgorithmName: String, maxCacheSize: Int, storageIdentifier: String, concurrentBatchSize: Int, maxConcurrent: Int) -> [String?] in
        let pHashes = calcPerceptualHashes(imageAppleIds: imageAppleIds, hashAlgorithmName: hashAlgorithmName, maxCacheSize: maxCacheSize, storageIdentifier: storageIdentifier, concurrentBatchSize: concurrentBatchSize, maxConcurrent: maxConcurrent);
        return pHashes
    }

    AsyncFunction("findSimilarImages") { (imageAppleIds: [String], maxHammingDistance: Int, hashAlgorithmName: String, maxCacheSize: Int, storageIdentifier: String, concurrentBatchSize: Int, maxConcurrent: Int) -> [[String]] in
        let pHashes = calcPerceptualHashes(imageAppleIds: imageAppleIds, hashAlgorithmName: hashAlgorithmName, maxCacheSize: maxCacheSize, storageIdentifier: storageIdentifier, concurrentBatchSize: concurrentBatchSize, maxConcurrent: maxConcurrent)
        var similarImages = [[String]]()

        sendEvent("find-similar-iteration", [
          "finished": 0,
          "total": pHashes.count - 1
        ])
        for i in 0..<pHashes.count - 1 {
            guard let pHash1 = pHashes[i] else {
                sendEvent("find-similar-iteration", [
                  "finished": i + 1,
                  "total": pHashes.count - 1
                ])
                continue
            }

            for j in (i + 1)..<pHashes.count {
                guard let pHash2 = pHashes[j], i < j else {
                    continue
                }

                let pHashDoubleArray1 = pHash1.map {Double(String($0)) ?? 0}
                let pHashDoubleArray2 = pHash2.map {Double(String($0)) ?? 0}

                let hammingDistance = calcHammingDistance(lhsData: pHashDoubleArray1, rhsData: pHashDoubleArray2)
                if hammingDistance <= maxHammingDistance {
                    similarImages.append([imageAppleIds[i], imageAppleIds[j]])
                }
            }

            sendEvent("find-similar-iteration", [
              "finished": i + 1,
              "total": pHashes.count - 1
            ])
        }

        return similarImages
    }

    AsyncFunction("findSimilarImagesKDTree") { (imageAppleIds: [String], maxHammingDistance: Int, hashAlgorithmName: String, nearestK: Int, maxCacheSize: Int, storageIdentifier: String, concurrentBatchSize: Int, maxConcurrent: Int) -> [[String]] in
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

        let pHashes = calcPerceptualHashes(imageAppleIds: imageAppleIds, hashAlgorithmName: hashAlgorithmName, maxCacheSize: maxCacheSize, storageIdentifier: storageIdentifier, concurrentBatchSize: concurrentBatchSize, maxConcurrent: maxConcurrent)
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


        sendEvent("find-similar-iteration", [
          "finished": 0,
          "total": points64D.count
        ])
        for (pointIndex, point) in points64D.enumerated() {
          if foundSimilarityIdsHashMap[point.appleId] != nil {
              sendEvent("find-similar-iteration", [
                "finished": pointIndex + 1,
                "total": points64D.count
              ])
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

          sendEvent("find-similar-iteration", [
            "finished": pointIndex + 1,
            "total": points64D.count
          ])
        }

        return similarImages
    }
  }
}
