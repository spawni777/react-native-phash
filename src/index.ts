import ReactNativePhashModule from './ReactNativePhashModule';

type HashAlgorithmName = "dHash" | "pHash" | "aHash";

export async function getImagePerceptualHash(
  imageIds: string | string[],
  hashAlgorithmName: HashAlgorithmName = "dHash"
): Promise<string[]> {
  if (imageIds?.length)
    return ReactNativePhashModule.getPerceptualHashes(imageIds, hashAlgorithmName);
  else
    return ReactNativePhashModule.getPerceptualHashes(
      [imageIds],
      hashAlgorithmName
    );
}

// GUESS IT DOESN'T WORK?????!!!!!
export async function findSimilarImagesCocoaImageHashing(
  imageIds: string | string[],
  hashAlgorithmName: HashAlgorithmName = "dHash"
): Promise<string[]> {
  if (imageIds?.length)
    return ReactNativePhashModule.findSimilarImagesCocoaImageHashing(
      imageIds,
      hashAlgorithmName
    );
  else
    return ReactNativePhashModule.findSimilarImagesCocoaImageHashing(
      [imageIds],
      hashAlgorithmName
    );
}

export async function findSimilarImages(
  imageIds: string | string[],
  maxHammingDistance: number = 5,
  hashAlgorithmName: HashAlgorithmName = "dHash"
): Promise<[string, string][]> {
  if (imageIds?.length)
    return ReactNativePhashModule.findSimilarImages(imageIds, maxHammingDistance, hashAlgorithmName);
  else
    return ReactNativePhashModule.findSimilarImages([imageIds], maxHammingDistance, hashAlgorithmName);
}

export async function findSimilarImagesKDTree(
  imageIds: string | string[],
  maxHammingDistance: number = 5,
  hashAlgorithmName: HashAlgorithmName = "dHash",
  nearestK: number = 2
): Promise<string[][]> {
  if (imageIds?.length)
    return ReactNativePhashModule.findSimilarImagesKDTree(
      imageIds,
      maxHammingDistance,
      hashAlgorithmName,
      nearestK
    );
  else
    return ReactNativePhashModule.findSimilarImagesKDTree(
      [imageIds],
      maxHammingDistance,
      hashAlgorithmName,
      nearestK
    );
}
