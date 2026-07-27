import SceneKit
import Metal

public final class GalaxyRenderer: NSObject, SCNSceneRendererDelegate {
    private var device: MTLDevice?

    public override init() {
        self.device = MTLCreateSystemDefaultDevice()
        super.init()
    }

    public func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        // Called every frame — future: custom Metal rendering passes
    }

    public func renderer(_ renderer: SCNSceneRenderer, didApplyAnimationsAtTime time: TimeInterval) {
        // Post-animation update hook
    }
}
