import 'package:flutter/material.dart';
import 'package:three_js/three_js.dart' as three;

/// View-only 3D dental model. Click-and-hold drag orbits 360°.
class ToothModel3D extends StatefulWidget {
  const ToothModel3D({
    super.key,
    this.asset = 'assets/tooth_model_3d_untextured.glb',
  });
  final String asset;

  @override
  State<ToothModel3D> createState() => _ToothModel3DState();
}

class _ToothModel3DState extends State<ToothModel3D> {
  late three.ThreeJS threeJs;
  three.OrbitControls? _controls;

  @override
  void initState() {
    super.initState();
    threeJs = three.ThreeJS(
      onSetupComplete: () => setState(() {}),
      setup: _setup,
    );
  }

  @override
  void dispose() {
    _controls?.dispose();
    threeJs.dispose();
    super.dispose();
  }

  Future<void> _setup() async {
    threeJs.scene = three.Scene();
    threeJs.scene.background = three.Color.fromHex32(0x0b1422);

    threeJs.camera = three.PerspectiveCamera(
      45,
      threeJs.width / threeJs.height,
      0.1,
      100,
    );
    threeJs.camera.position.setValues(0, 0, 3.4);

    // lighting
    threeJs.scene.add(three.AmbientLight(0xffffff, 0.9));
    final key = three.DirectionalLight(0xffffff, 1.1)
      ..position.setValues(2, 3, 4);
    threeJs.scene.add(key);
    final fill = three.DirectionalLight(0xffffff, 0.45)
      ..position.setValues(-3, -1, -2);
    threeJs.scene.add(fill);

    // orbit controls (drag to rotate)
    _controls = three.OrbitControls(threeJs.camera, threeJs.globalKey)
      ..enableDamping = true
      ..dampingFactor = 0.08
      ..enablePan = false
      ..minDistance = 1.8
      ..maxDistance = 8.0;

    // load the model
    final loader = three.GLTFLoader();
    final gltf = await loader.fromAsset(widget.asset);
    if (gltf != null) {
      threeJs.scene.add(gltf.scene);
    }

    threeJs.addAnimationEvent((dt) {
      _controls?.update();
    });
  }

  @override
  Widget build(BuildContext context) => threeJs.build();
}
