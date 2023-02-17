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

func calcHammingDistance(lhsData: OSHashType, rhsData: OSHashType, algorithmName: String) -> OSHashDistanceType {
    switch algorithmName {
      case "dHash":
          return OSImageHashing.sharedInstance().hashDistance(lhsData, to: rhsData, with: .dHash)
      case "pHash":
          return OSImageHashing.sharedInstance().hashDistance(lhsData, to: rhsData, with: .pHash)
      default:
          return OSImageHashing.sharedInstance().hashDistance(lhsData, to: rhsData, with: .aHash)
    }
}

func calcPerceptualHashes(imageAppleIds: [String], algorithmName: String) -> [OSHashType?] {
  let imageHashing = OSImageHashing.sharedInstance()

  func calcPerceptualHash(imageData: Data, algorithmName: String) -> OSHashType {
    switch algorithmName {
      case "dHash":
          return imageHashing.hashImageData(imageData, with: .dHash)
      case "pHash":
          return imageHashing.hashImageData(imageData, with: .pHash)
      default:
          return imageHashing.hashImageData(imageData, with: .aHash)
    }
  }

  var dHashes: [OSHashType?] = []

  let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: imageAppleIds, options: nil)

  fetchResult.enumerateObjects{  (asset, count, stop) in
    // assuming you have a `PHAsset` instance called `asset`:
    let options = PHImageRequestOptions()
    options.isSynchronous = true // ensure the result is returned immediately

    PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { (imageData, dataUTI, orientation, info) in
        guard let imageData = imageData else {
            // handle error
            dHashes.append(nil)
            return
        }

        // process the image data
        let dHash = calcPerceptualHash(imageData: imageData, algorithmName: algorithmName)

        dHashes.append(dHash)
    }
  }

  return dHashes
}

public class ReactNativePhashModule: Module {
  // Each module class must implement the definition function. The definition consists of components
  // that describes the module's functionality and behavior.
  // See https://docs.expo.dev/modules/module-api for more details about available components.
  public func definition() -> ModuleDefinition {
    // Sets the name of the module that JavaScript code will use to refer to the module. Takes a string as an argument.
    // Can be inferred from module's class name, but it's recommended to set it explicitly for clarity.
    // The module will be accessible from `requireNativeModule('ReactNativePhash')` in JavaScript.
    Name("ReactNativePhash")

    // Defines a JavaScript function that always returns a Promise and whose native code
    // is by default dispatched on the different thread than the JavaScript runtime runs on.
    AsyncFunction("getPerceptualHashes") { (imageAppleIds: [String], algorithmName: String) -> [String?] in
        let dHashes = calcPerceptualHashes(imageAppleIds: imageAppleIds, algorithmName: algorithmName);

        var dHashesStrings: [String?] = []

        for dHash in dHashes {
          if (dHash == nil) {
            dHashesStrings.append(nil);
            continue
          }
          let binaryString = String(dHash!, radix: 2)
          let paddedBinaryString = binaryString.padding(toLength: 64, withPad: "0", startingAt: 0)

          dHashesStrings.append(paddedBinaryString)
        }

        return dHashesStrings
    }

    AsyncFunction("findSimilarImagesCocoaImageHashing") { (imageAppleIds: [String], algorithmName: String) -> [String] in
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

    AsyncFunction("findSimilarImages") { (imageAppleIds: [String], maxHammingDistance: Int, algorithmName: String) -> [[String]] in
        let dHashes = calcPerceptualHashes(imageAppleIds: imageAppleIds, algorithmName: algorithmName)
        var similarImages = [[String]]()

        for i in 0..<dHashes.count - 1 {
            guard let dHash1 = dHashes[i] else {
                continue
            }

            for j in (i + 1)..<dHashes.count {
                guard let dHash2 = dHashes[j], i < j else {
                    continue
                }

                let hammingDistance = calcHammingDistance(lhsData: dHash1 as OSHashType, rhsData: dHash2 as OSHashType, algorithmName: algorithmName)
                if hammingDistance <= maxHammingDistance {
                    similarImages.append([imageAppleIds[i], imageAppleIds[j]])
                }
            }
        }

        return similarImages
    }

    AsyncFunction("findSimilarImagesKDTree") { (imageAppleIds: [String], maxHammingDistance: Int, algorithmName: String) -> [[String]] in
        let dHashes = calcPerceptualHashes(imageAppleIds: imageAppleIds, algorithmName: algorithmName)
        let kdTree = KDTree<Double>(values: dHashes, dimensions: dHashes[0].count)
        var similarImages = [[String]]()

        for (i, dHash1) in dHashes.enumerated() {
            let nearestNeighbors = kdTree.findNeighbors(of: dHash1, maxCount: 4, distance: euclideanDistance)
            let filteredNeighbors = nearestNeighbors.filter { $0.index > i && $0.distance <= Double(maxHammingDistance) }

            for neighbor in filteredNeighbors {
                similarImages.append([imageAppleIds[i], imageAppleIds[neighbor.index]])
            }
        }

        return similarImages
    }
  }
}
