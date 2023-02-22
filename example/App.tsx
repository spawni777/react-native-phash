import * as MediaLibrary from "expo-media-library";
import { useEffect } from "react";
import { Button, StyleSheet, Text, View } from "react-native";
// import * as ReactNativePhash from "react-native-phash";
import {
  getImagesPHashIterative,
  getImagesPHashConcurrently,
  findSimilarIterative,
  findSimilarIterativeKDTree,
  findSimilarConcurrentlyPartial,
  addListener,
  findSimilarConcurrently,
} from "react-native-phash";

const pHashCalculatedSubscription = addListener(
  "pHash-calculated",
  ({ finished, total }) => {
    const percentage = Math.floor((finished / total) * 10000) / 100;
    console.log(`pHash-calculated: ${percentage}%`);

    // if (percentage >= 100) {
    //   pHashCalculatedSubscription.remove();
    // }
  }
);
const findSimilarIterationSubscription = addListener(
  "find-similar-iteration",
  ({ finished, total }) => {
    const percentage = Math.floor((finished / total) * 10000) / 100;
    console.log(`find-similar-iteration: ${percentage}%`);

    // if (percentage >= 100) {
    //   findSimilarIterationSubscription.remove();
    // }
  }
);

const calcAndLog1 = async () => {
  const { assets } = await MediaLibrary.getAssetsAsync({
    first: 200,
    mediaType: "photo",
  });

  const imagesPerceptualHashes = await getImagesPHashIterative(
    assets.map((asset) => asset.id),
    {
      maxCacheSize: 0,
    }
  );
  console.log(JSON.stringify(imagesPerceptualHashes, null, 2));
  console.log(imagesPerceptualHashes.length);
};

const calcAndLog2 = async () => {
  const { assets } = await MediaLibrary.getAssetsAsync({
    first: 200,
    mediaType: "photo",
  });

  const imagesPerceptualHashes = await getImagesPHashConcurrently(
    assets.map((asset) => asset.id),
    {
      maxCacheSize: 0,
      concurrentBatchSize: 1,
      maxConcurrent: 10000,
    }
  );
  console.log(JSON.stringify(imagesPerceptualHashes, null, 2));
  console.log(imagesPerceptualHashes.length);
};

const calcAndLog3 = async () => {
  const { assets } = await MediaLibrary.getAssetsAsync({
    first: 200,
    mediaType: "photo",
  });

  const similarImages = await findSimilarIterative(
    assets.map((asset) => asset.id),
    {
      maxCacheSize: 0,
    }
  );
  console.log(JSON.stringify(similarImages, null, 2));
  console.log(similarImages.length);
};

const calcAndLog4 = async () => {
  const { assets } = await MediaLibrary.getAssetsAsync({
    first: 1000,
    mediaType: "photo",
  });

  const similarImagesKDTree = await findSimilarIterativeKDTree(
    assets.map((asset) => asset.id),
    {
      maxCacheSize: 0,
      nearestK: 1,
      maxHammingDistance: 1,
      hashAlgorithmName: "pHash",
    }
  );
  console.log(JSON.stringify(similarImagesKDTree, null, 2));
  console.log(similarImagesKDTree.length);
};

const calcAndLog5 = async () => {
  const { assets } = await MediaLibrary.getAssetsAsync({
    first: 1000,
    mediaType: "photo",
  });

  const similarImagesKDTree = await findSimilarConcurrentlyPartial(
    assets.map((asset) => asset.id),
    {
      maxCacheSize: 200,
      concurrentBatchSize: 50,
      maxConcurrent: 100,
      nearestK: 1,
      hashAlgorithmName: "pHash",
      maxHammingDistance: 1,
    }
  );
  console.log(JSON.stringify(similarImagesKDTree, null, 2));
  console.log(similarImagesKDTree.length);
};

const calcAndLog6 = async () => {
  const { assets } = await MediaLibrary.getAssetsAsync({
    first: 1000,
    mediaType: "photo",
  });

  const similarImagesKDTree = await findSimilarConcurrently(
    assets.map((asset) => asset.id),
    {
      maxCacheSize: 200,
      concurrentBatchSize: 50,
      maxConcurrent: 100,
      nearestK: 1,
      hashAlgorithmName: "pHash",
      maxHammingDistance: 1,
    }
  );
  console.log(JSON.stringify(similarImagesKDTree, null, 2));
  console.log(similarImagesKDTree.length);
};

export default function App() {
  useEffect(() => {
    (async () => {
      const { status } = await MediaLibrary.requestPermissionsAsync();
      if (status !== "granted") {
        console.log('GRANT PERMISSIONS!');
      }
    })();
  }, []);

  return (
    <View style={styles.container}>
      <Text>Hello there!</Text>
      <Button title={"getImagesPHashIterative"} onPress={calcAndLog1}/>
      <Button title={"getImagesPHashConcurrently"} onPress={calcAndLog2}/>
      <Button title={"findSimilarIterative"} onPress={calcAndLog3}/>
      <Button title={"findSimilarIterativeKDTree"} onPress={calcAndLog4}/>
      <Button title={"findSimilarConcurrentlyPartial"} onPress={calcAndLog5}/>
      <Button title={"findSimilarConcurrently"} onPress={calcAndLog6}/>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#fff',
    alignItems: 'center',
    justifyContent: 'center',
  },
});
