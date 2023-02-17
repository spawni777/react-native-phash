import ExpoModulesCore
import CocoaImageHashing
import Photos
import KDTree

class ImageObject {
  var data: Data
  var appleId: String

  init(data: Data, appleId: String){
    self.data = data
    self.appleId = appleId
  }
}

func calcHammingDistance(lhsData: OSHashType, rhsData: OSHashType, hashAlgorithmName: String) -> OSHashDistanceType {
    switch hashAlgorithmName {
      case "dHash":
          return OSImageHashing.sharedInstance().hashDistance(lhsData, to: rhsData, with: .dHash)
      case "pHash":
          return OSImageHashing.sharedInstance().hashDistance(lhsData, to: rhsData, with: .pHash)
      default:
          return OSImageHashing.sharedInstance().hashDistance(lhsData, to: rhsData, with: .aHash)
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
  func calcPerceptualHashes(imageAppleIds: [String], hashAlgorithmName: String) -> [OSHashType?] {
    let imageHashing = OSImageHashing.sharedInstance()

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

    var pHashes: [OSHashType?] = []

    let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: imageAppleIds, options: nil)

    sendEvent("PHAssets-fetched", [:])

    fetchResult.enumerateObjects{  (asset, count, stop) in
      // assuming you have a `PHAsset` instance called `asset`:
      let options = PHImageRequestOptions()
      options.isSynchronous = true // ensure the result is returned immediately

      PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { (imageData, dataUTI, orientation, info) in
          guard let imageData = imageData else {
              // handle error
              pHashes.append(nil)
              return
          }

          // process the image data
          let pHash = calcPerceptualHash(imageData: imageData, hashAlgorithmName: hashAlgorithmName)

          pHashes.append(pHash)
          self.sendEvent("pHash-calculated", [
            "finished": count + 1,
            "total": imageAppleIds.count
          ])
      }
    }

    return pHashes
  }

  public func definition() -> ModuleDefinition {
    // Sets the name of the module that JavaScript code will use to refer to the module. Takes a string as an argument.
    // Can be inferred from module's class name, but it's recommended to set it explicitly for clarity.
    // The module will be accessible from `requireNativeModule('ReactNativePhash')` in JavaScript.
    Name("ReactNativePhash")

    Events("PHAssets-fetched", "pHash-calculated", "KDTree-generation-start", "KDTree-generation-end", "find-similar-iteration")

    // Defines a JavaScript function that always returns a Promise and whose native code
    // is by default dispatched on the different thread than the JavaScript runtime runs on.
    AsyncFunction("getPerceptualHashes") { (imageAppleIds: [String], hashAlgorithmName: String) -> [String?] in
        let pHashes = calcPerceptualHashes(imageAppleIds: imageAppleIds, hashAlgorithmName: hashAlgorithmName);

        var pHashesStrings: [String?] = []

        for pHash in pHashes {
          if (pHash == nil) {
            pHashesStrings.append(nil);
            continue
          }
          let binaryString = String(pHash!, radix: 2)
          let paddedBinaryString = binaryString.padding(toLength: 64, withPad: "0", startingAt: 0)

          pHashesStrings.append(paddedBinaryString)
        }

        return pHashesStrings
    }

    AsyncFunction("findSimilarImagesCocoaImageHashing") { (imageAppleIds: [String], hashAlgorithmName: String) -> [String] in
        let imageHashing = OSImageHashing.sharedInstance()
        var images: [ImageObject] = []

        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: imageAppleIds, options: nil)

        fetchResult.enumerateObjects{  (asset, count, stop) in
          // assuming you have a `PHAsset` instance called `asset`:
          let options = PHImageRequestOptions()
          options.isSynchronous = true // ensure the result is returned immediately

          PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { (imageData, dataUTI, orientation, info) in
              guard let imageData = imageData else {
                  return
              }

              images.append(ImageObject(data: imageData, appleId: imageAppleIds[count]))
          }
        }

        let similarImages = imageHashing.similarImages(withProvider: .pHash) {
            if images.count > 0 {
                let imageObject = images.removeFirst()

                let data = imageObject.data
                let appleId = imageObject.appleId

                return OSTuple<NSString, NSData>(first: appleId as NSString,
                                                 andSecond: data as NSData)
            } else {
                return OSTuple<NSString, NSData>(first: "" as NSString,
                                                 andSecond: NSData())
            }
        }

        var result:[String] = [];

        for tuple in similarImages {
          let name = tuple.first! as String
          result.append(name)
        }

        return result
    }

    AsyncFunction("findSimilarImages") { (imageAppleIds: [String], maxHammingDistance: Int, hashAlgorithmName: String) -> [[String]] in
        let pHashes = calcPerceptualHashes(imageAppleIds: imageAppleIds, hashAlgorithmName: hashAlgorithmName)
        var similarImages = [[String]]()

        for i in 0..<pHashes.count - 1 {
            guard let pHash1 = pHashes[i] else {
                continue
            }

            for j in (i + 1)..<pHashes.count {
                guard let pHash2 = pHashes[j], i < j else {
                    continue
                }

                let hammingDistance = calcHammingDistance(lhsData: pHash1 as OSHashType, rhsData: pHash2 as OSHashType, hashAlgorithmName: hashAlgorithmName)
                if hammingDistance <= maxHammingDistance {
                    similarImages.append([imageAppleIds[i], imageAppleIds[j]])
                }
            }

            sendEvent("find-similar-iteration", [
              "finished": i + 1,
              "total": pHashes.count
            ])
        }

        return similarImages
    }

    AsyncFunction("findSimilarImagesKDTree") { (imageAppleIds: [String], maxHammingDistance: Int, hashAlgorithmName: String, nearestK: Int) -> [[String]] in
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

        let pHashes = calcPerceptualHashes(imageAppleIds: imageAppleIds, hashAlgorithmName: hashAlgorithmName)
        var points64D = [Point64D]()

        sendEvent("KDTree-generation-start", [:])

        for (index, pHash) in pHashes.enumerated() {
          if (pHash == nil) {
            continue
          }
          let binaryString = String(pHash!, radix: 2).replacingOccurrences(of: "-", with: "")
          let paddedBinaryString = binaryString.padding(toLength: 64, withPad: "0", startingAt: 0)
          let binaryStringArray = paddedBinaryString.map { String($0) }
          let doubleArray = binaryStringArray.map { Double($0) ?? 0 }

          points64D.append(Point64D(coordinates: doubleArray, appleId: imageAppleIds[index]))
        }

        let kdTree: KDTree<Point64D> = KDTree(values: points64D)
        sendEvent("KDTree-generation-end", [:])
        var similarImages = [[String]]()
        var foundSimilarityIdsHashMap = [String: Int]()

        for (pointIndex, point) in points64D.enumerated() {
          if let val = foundSimilarityIdsHashMap[point.appleId] {
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
            if let val = foundSimilarityIdsHashMap[neighbor.appleId] {
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
