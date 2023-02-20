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

type EventNameEnum = "pHash-calculated" | "find-similar-iteration";

type PHashEvent = {
  finished: number;
  total: number;
};

type ReturnEventMap = {
  "pHash-calculated": PHashEvent;
  "find-similar-iteration": PHashEvent;
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
  concurrentBatchSize?: number;
  maxConcurrent?: number;
};

export async function getImagesPerceptualHashes(
  imageIds: string | string[],
  {
    hashAlgorithmName = "dHash",
    maxCacheSize = 10000,
    storageIdentifier = "Spawni-PHash",
    concurrentBatchSize = 10,
    maxConcurrent = 10,
  }: PHashOptions = {}
): Promise<string[]> {
  const appleIds = imageIds.length ? imageIds : [imageIds];
  maxCacheSize = Math.max(0, maxCacheSize);

  return ReactNativePhashModule.getPerceptualHashes(
    appleIds,
    hashAlgorithmName,
    maxCacheSize,
    storageIdentifier,
    concurrentBatchSize,
    maxConcurrent
  );
}

export type FindSimilarImagesOptions = PHashOptions & {
  maxHammingDistance?: MaxHammingDistance;
};

export async function findSimilarImages(
  imageIds: string | string[],
  {
    hashAlgorithmName = "dHash",
    maxHammingDistance = 5,
    maxCacheSize = 10000,
    storageIdentifier = "Spawni-PHash",
    concurrentBatchSize = 10,
    maxConcurrent = 10,
  }: FindSimilarImagesOptions = {}
): Promise<[string, string][]> {
  const appleIds = imageIds?.length ? imageIds : [imageIds];
  maxCacheSize = Math.max(0, maxCacheSize);

  return ReactNativePhashModule.findSimilarImages(
    appleIds,
    maxHammingDistance,
    hashAlgorithmName,
    maxCacheSize,
    storageIdentifier,
    concurrentBatchSize,
    maxConcurrent
  );
}

type FindSimilarImagesKDTreeOptions = FindSimilarImagesOptions & {
  nearestK?: NearestK;
};

export async function findSimilarImagesKDTree(
  imageIds: string | string[],
  {
    maxHammingDistance = 5,
    hashAlgorithmName = "dHash",
    nearestK = 2,
    maxCacheSize = 10000,
    storageIdentifier = "Spawni-PHash",
    concurrentBatchSize = 10,
    maxConcurrent = 10,
  }: FindSimilarImagesKDTreeOptions = {}
): Promise<string[][]> {
  const appleIds = imageIds?.length ? imageIds : [imageIds];
  maxCacheSize = Math.max(0, maxCacheSize);

  return ReactNativePhashModule.findSimilarImagesKDTree(
    appleIds,
    maxHammingDistance,
    hashAlgorithmName,
    nearestK,
    maxCacheSize,
    storageIdentifier,
    concurrentBatchSize,
    maxConcurrent,
  );
}
