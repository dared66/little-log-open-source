import 'native_density_layout_test.dart' as density;
import 'store_screenshots_test.dart' as store;

// Synthetic captures and layout assertions at the device's actual density.
void main() {
  density.main();
  store.main();
}
