import ReactNativePhashModule from './ReactNativePhashModule';

type AlgorithmName = "dHash" | "pHash" | "aHash";

export async function getImagePerceptualHash(
  imageIds: string | string[],
  algorithmName: AlgorithmName = "dHash"
): Promise<string[]> {
  if (imageIds?.length)
    return ReactNativePhashModule.getPerceptualHashes(imageIds, algorithmName);
  else
    return ReactNativePhashModule.getPerceptualHashes(
      [imageIds],
      algorithmName
    );
}

// GUESS IT DOESN'T WORK?????!!!!!
export async function findSimilarImagesCocoaImageHashing(
  imageIds: string | string[],
  algorithmName: AlgorithmName = "dHash"
): Promise<string[]> {
  if (imageIds?.length)
    return ReactNativePhashModule.findSimilarImagesCocoaImageHashing(
      imageIds,
      algorithmName
    );
  else
    return ReactNativePhashModule.findSimilarImagesCocoaImageHashing(
      [imageIds],
      algorithmName
    );
}

export async function findSimilarImages(
  imageIds: string | string[],
  maxHammingDistance: number = 5,
  algorithmName: AlgorithmName = "dHash"
): Promise<[string, string][]> {
  if (imageIds?.length)
    return ReactNativePhashModule.findSimilarImages(imageIds, maxHammingDistance, algorithmName);
  else
    return ReactNativePhashModule.findSimilarImages([imageIds], maxHammingDistance, algorithmName);
}
