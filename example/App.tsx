import * as MediaLibrary from "expo-media-library";
import { useEffect } from "react";
import { Button, StyleSheet, Text, View } from "react-native";
// import * as ReactNativePhash from "react-native-phash";
import {
  findSimilarImagesKDTree,
  findSimilarImages,
  addListener,
  getImagesPerceptualHashes,
} from "react-native-phash";

const pHashCalculatedSubscription = addListener(
  "pHash-calculated",
  ({ finished, total }) => {
    const percentage = Math.floor((finished / total) * 10000) / 100;
    console.log(`pHash-calculated: ${percentage}%`);

    if (percentage >= 100) {
      pHashCalculatedSubscription.remove();
    }
  }
);
const findSimilarIterationSubscription = addListener(
  "find-similar-iteration",
  ({ finished, total }) => {
    const percentage = Math.floor((finished / total) * 10000) / 100;
    console.log(`find-similar-iteration: ${percentage}%`);

    if (percentage >= 100) {
      findSimilarIterationSubscription.remove();
    }
  }
);

const calcAndLog1 = async () => {
  const { assets } = await MediaLibrary.getAssetsAsync({
    first: 1000,
    mediaType: "photo",
  });

  const imagesPerceptualHashes = await getImagesPerceptualHashes(
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
    first: 1000,
    mediaType: "photo",
  });

  const similarImages = await findSimilarImages(
    assets.map((asset) => asset.id),
    {
      maxCacheSize: 0,
    }
  );
  console.log(JSON.stringify(similarImages, null, 2));
};

const calcAndLog3 = async () => {
  const { assets } = await MediaLibrary.getAssetsAsync({
    first: 1000,
    mediaType: "photo",
  });

  const similarImagesKDTree = await findSimilarImagesKDTree(
    assets.map((asset) => asset.id),
    { maxCacheSize: 0 }
  );
  console.log(JSON.stringify(similarImagesKDTree, null, 2));
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
      <Button title={"Hash"} onPress={calcAndLog1}/>
      <Button title={"similar"} onPress={calcAndLog2}/>
      <Button title={"similarKDTree"} onPress={calcAndLog3}/>
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
