import * as MediaLibrary from "expo-media-library";
import { useEffect } from "react";
import { StyleSheet, Text, View } from "react-native";
// import * as ReactNativePhash from "react-native-phash";
import { getImagePerceptualHash, findSimilarImages, findSimilarImagesKDTree, addListener } from "react-native-phash";

let images: MediaLibrary.Asset[];

export default function App() {
  useEffect(() => {
    (async () => {
      const { status } = await MediaLibrary.requestPermissionsAsync();
      if (status !== "granted") return;

      const { assets } = await MediaLibrary.getAssetsAsync({ first: 100 });
      images = assets;

      const fileExtension = assets[0].filename.split('.')[1];
      console.log(JSON.stringify(assets[0], null, 2));

      addListener('find-similar-iteration', ({finished}) => {
        console.log('find-similar-iteration', finished);
      });
      addListener('KDTree-generation-start', ({}) => {
        console.log('KDTree-generation-start');
      });
      addListener('KDTree-generation-end', () => {
        console.log('KDTree-generation-end');
      });
      addListener('pHash-calculated', ({finished}) => {
        console.log('pHash-calculated', finished);
      });

      // const libPath = getAssetsLibraryPath('jpg', assets[0].id);
      // console.log(libPath);

      const result = await findSimilarImagesKDTree(
        assets.map((asset) => asset.id),
        5,
        'dHash',
        2
      );

      console.log(JSON.stringify(result, null, 2));

      // const localUriFetchPromises: Promise<void>[] = [];
      // const localUris: string[] = [];
      //
      // assets.forEach((asset) => {
      //   // @ts-ignore
      //   const promise = MediaLibrary.getAssetInfoAsync(asset.id).then(
      //     (assetInfo) => {
      //       localUris.push(assetInfo.localUri as string);
      //     }
      //   );
      //   localUriFetchPromises.push(promise);
      // });
      //
      // await Promise.all(localUriFetchPromises);
      //
      // const result = await ReactNativePhash.imagePhash(localUris);
      //
      // console.log(JSON.stringify(result, null, 2));
    })();
  }, []);
  // ReactNativePhash.imagePhash();

  // console.log(JSON.stringify(assets, null, 2));
  return (
    <View style={styles.container}>
      <Text>Hello there!</Text>
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
