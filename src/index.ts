import { EventEmitter, Subscription } from "expo-modules-core";

import ReactNativePhashModule from "./ReactNativePhashModule";

type Enumerate<
  N extends number,
  Acc extends number[] = []
> = Acc["length"] extends N
  ? Acc[number]
  : Enumerate<N, [...Acc, Acc["length"]]>;

type Range<F extends number, T extends number> = Exclude<
  Enumerate<T>,
  Enumerate<F>
>;

export type NearestK = Range<1, 100>;
export type MaxHammingDistance = Range<1, 64>;
export type HashAlgorithmName = "dHash" | "pHash" | "aHash";

type EventNameEnum =
  | "pHash-calculated"
  | "find-similar-iteration"
  | "md5-calculated";

type PHashEvent = {
  finished: number;
  total: number;
};

type ReturnEventMap = {
  "pHash-calculated": PHashEvent;
  "find-similar-iteration": PHashEvent;
  "md5-calculated": PHashEvent;
};

function makeId(length) {
  let result = "";
  const characters =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
  const charactersLength = characters.length;
  let counter = 0;
  while (counter < length) {
    result += characters.charAt(Math.floor(Math.random() * charactersLength));
    counter += 1;
  }
  return result;
}

const emitter = new EventEmitter(ReactNativePhashModule);
// add clear listeners to remove warnings
emitter.addListener<"pHash-calculated">("pHash-calculated", () => {});
emitter.addListener<"pHash-calculated">("find-similar-iteration", () => {});
emitter.addListener<"md5-calculated">("md5-calculated", () => {});

export const subscriptions: { [key: string]: Subscription } = {};
export function addListener<T extends EventNameEnum>(
  eventName: T,
  listener: (event: ReturnEventMap[T]) => void,
  listenerId: string = makeId(10)
): Subscription {
  const subscription = emitter.addListener<ReturnEventMap[T]>(eventName, listener);

  subscriptions[listenerId] = subscription;
  return subscription;
}

export type PHashOptions = {
  hashAlgorithmName?: HashAlgorithmName;
  maxCacheSize?: number;
  storageIdentifier?: string;
  imageQuality?: "fastFormat" | "highQualityFormat";
};

export async function getImagesPHashIterative(
  imageAppleIds: string | string[],
  {
    hashAlgorithmName = "dHash",
    maxCacheSize = 10000,
    storageIdentifier = "Spawni-PHash",
    imageQuality = "highQualityFormat",
  }: PHashOptions = {}
): Promise<string[]> {
  const appleIds = imageAppleIds.length ? imageAppleIds : [imageAppleIds];
  maxCacheSize = Math.max(0, maxCacheSize);

  return ReactNativePhashModule.getPHashesIterative(appleIds, {
    hashAlgorithmName,
    maxCacheSize,
    storageIdentifier,
    imageQuality,
  });
}

export type HashOptions = {
  maxCacheSize?: number;
  storageIdentifier?: string;
};

export async function getImagesDuplicatesIterative(
  imageAppleIds: string | string[],
  { maxCacheSize = 10000, storageIdentifier = "Spawni-Hash" }: HashOptions = {}
): Promise<string[]> {
  const appleIds = imageAppleIds.length ? imageAppleIds : [imageAppleIds];
  maxCacheSize = Math.max(0, maxCacheSize);

  return ReactNativePhashModule.findDuplicatesIterative(appleIds, {
    maxCacheSize,
    storageIdentifier,
  });
}

export type PHashConcurrentlyOptions = PHashOptions & {
  concurrentBatchSize?: number;
  maxConcurrent?: number;
};

export async function getImagesPHashConcurrently(
  imageAppleIds: string | string[],
  {
    hashAlgorithmName = "dHash",
    maxCacheSize = 10000,
    storageIdentifier = "Spawni-PHash",
    imageQuality = "highQualityFormat",
    concurrentBatchSize = 10,
    maxConcurrent = 10,
  }: PHashConcurrentlyOptions = {}
): Promise<string[]> {
  const appleIds = imageAppleIds.length ? imageAppleIds : [imageAppleIds];
  maxCacheSize = Math.max(0, maxCacheSize);
  maxConcurrent = Math.max(1, maxConcurrent);
  concurrentBatchSize = Math.max(1, concurrentBatchSize);

  return ReactNativePhashModule.getPHashesConcurrently(appleIds, {
    hashAlgorithmName,
    maxCacheSize,
    storageIdentifier,
    imageQuality,
    maxConcurrent,
    concurrentBatchSize,
  });
}

export type FindSimilarOptions = PHashOptions & {
  maxHammingDistance?: MaxHammingDistance;
};

export async function findSimilarIterativeOld(
  imageAppleIds: string | string[],
  {
    hashAlgorithmName = "dHash",
    maxHammingDistance = 5,
    maxCacheSize = 10000,
    storageIdentifier = "Spawni-PHash",
    imageQuality = "highQualityFormat",
  }: FindSimilarOptions = {}
): Promise<[string, string][]> {
  const appleIds = imageAppleIds?.length ? imageAppleIds : [imageAppleIds];
  maxCacheSize = Math.max(0, maxCacheSize);

  return ReactNativePhashModule.findSimilarIterativeOld(appleIds, {
    maxHammingDistance,
    hashAlgorithmName,
    maxCacheSize,
    storageIdentifier,
    imageQuality,
  });
}

export type FindSimilarOptionsUpdated = FindSimilarOptions & {
  nearestK?: NearestK;
};

export async function findSimilarIterative(
  imageAppleIds: string | string[],
  {
    hashAlgorithmName = "dHash",
    maxHammingDistance = 5,
    maxCacheSize = 10000,
    storageIdentifier = "Spawni-PHash",
    nearestK = 1,
    imageQuality = "highQualityFormat",
  }: FindSimilarOptionsUpdated = {}
): Promise<[string, string][]> {
  const appleIds = imageAppleIds?.length ? imageAppleIds : [imageAppleIds];
  maxCacheSize = Math.max(0, maxCacheSize);

  return ReactNativePhashModule.findSimilarIterative(appleIds, {
    maxHammingDistance,
    hashAlgorithmName,
    maxCacheSize,
    nearestK,
    storageIdentifier,
    imageQuality,
  });
}

type FindSimilarKDTreeOptions = FindSimilarOptions & {
  nearestK?: NearestK;
};

export async function findSimilarIterativeKDTree(
  imageAppleIds: string | string[],
  {
    maxHammingDistance = 5,
    hashAlgorithmName = "dHash",
    nearestK = 1,
    maxCacheSize = 10000,
    storageIdentifier = "Spawni-PHash",
    imageQuality = "highQualityFormat",
  }: FindSimilarKDTreeOptions = {}
): Promise<string[][]> {
  const appleIds = imageAppleIds?.length ? imageAppleIds : [imageAppleIds];
  maxCacheSize = Math.max(0, maxCacheSize);

  return ReactNativePhashModule.findSimilarIterativeKDTree(appleIds, {
    maxHammingDistance,
    hashAlgorithmName,
    maxCacheSize,
    storageIdentifier,
    imageQuality,
    nearestK,
  });
}

type FindSimilarConcurrentlyOptions = FindSimilarKDTreeOptions & {
  concurrentBatchSize?: number;
  maxConcurrent?: number;
};

export async function findSimilarConcurrentlyPartial(
  imageAppleIds: string | string[],
  {
    maxHammingDistance = 5,
    hashAlgorithmName = "dHash",
    nearestK = 1,
    maxCacheSize = 10000,
    storageIdentifier = "Spawni-PHash",
    concurrentBatchSize = 10,
    maxConcurrent = 10,
    imageQuality = "highQualityFormat",
  }: FindSimilarConcurrentlyOptions = {}
): Promise<string[][]> {
  const appleIds = imageAppleIds?.length ? imageAppleIds : [imageAppleIds];
  maxCacheSize = Math.max(0, maxCacheSize);
  maxConcurrent = Math.max(1, maxConcurrent);
  concurrentBatchSize = Math.max(1, concurrentBatchSize);

  return ReactNativePhashModule.findSimilarConcurrentlyPartial(appleIds, {
    maxHammingDistance,
    hashAlgorithmName,
    maxCacheSize,
    storageIdentifier,
    concurrentBatchSize,
    maxConcurrent,
    imageQuality,
    nearestK,
  });
}

export async function findSimilarConcurrentlyOld(
  imageAppleIds: string | string[],
  {
    maxHammingDistance = 5,
    hashAlgorithmName = "dHash",
    nearestK = 1,
    maxCacheSize = 10000,
    storageIdentifier = "Spawni-PHash",
    concurrentBatchSize = 10,
    maxConcurrent = 10,
    imageQuality = "highQualityFormat",
  }: FindSimilarConcurrentlyOptions = {}
): Promise<string[][]> {
  const appleIds = imageAppleIds?.length ? imageAppleIds : [imageAppleIds];
  maxCacheSize = Math.max(0, maxCacheSize);
  maxConcurrent = Math.max(1, maxConcurrent);
  concurrentBatchSize = Math.max(1, concurrentBatchSize);

  return ReactNativePhashModule.findSimilarConcurrentlyOld(appleIds, {
    maxHammingDistance,
    hashAlgorithmName,
    maxCacheSize,
    storageIdentifier,
    concurrentBatchSize,
    maxConcurrent,
    imageQuality,
    nearestK,
  });
}

export async function findSimilarConcurrently(
  imageAppleIds: string | string[],
  {
    maxHammingDistance = 5,
    hashAlgorithmName = "dHash",
    nearestK = 1,
    maxCacheSize = 10000,
    storageIdentifier = "Spawni-PHash",
    concurrentBatchSize = 10,
    maxConcurrent = 10,
    imageQuality = "highQualityFormat",
  }: FindSimilarConcurrentlyOptions = {}
): Promise<string[][]> {
  const appleIds = imageAppleIds?.length ? imageAppleIds : [imageAppleIds];
  maxCacheSize = Math.max(0, maxCacheSize);
  maxConcurrent = Math.max(1, maxConcurrent);
  concurrentBatchSize = Math.max(1, concurrentBatchSize);

  return ReactNativePhashModule.findSimilarConcurrently(appleIds, {
    maxHammingDistance,
    hashAlgorithmName,
    maxCacheSize,
    storageIdentifier,
    concurrentBatchSize,
    maxConcurrent,
    imageQuality,
    nearestK,
  });
}

export async function findSimilarConcurrently2(
  imageAppleIds: string | string[],
  {
    maxHammingDistance = 5,
    hashAlgorithmName = "dHash",
    nearestK = 1,
    maxCacheSize = 10000,
    storageIdentifier = "Spawni-PHash",
    concurrentBatchSize = 10,
    maxConcurrent = 10,
    imageQuality = "highQualityFormat",
  }: FindSimilarConcurrentlyOptions = {}
): Promise<string[][]> {
  const appleIds = imageAppleIds?.length ? imageAppleIds : [imageAppleIds];
  maxCacheSize = Math.max(0, maxCacheSize);
  maxConcurrent = Math.max(1, maxConcurrent);
  concurrentBatchSize = Math.max(1, concurrentBatchSize);

  return ReactNativePhashModule.findSimilarConcurrently2(appleIds, {
    maxHammingDistance,
    hashAlgorithmName,
    maxCacheSize,
    storageIdentifier,
    concurrentBatchSize,
    maxConcurrent,
    imageQuality,
    nearestK,
  });
}
