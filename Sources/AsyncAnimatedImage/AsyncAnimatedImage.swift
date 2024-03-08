import SwiftUI
import Gifu

protocol GIFAnimatableDelegate: AnyObject {
    func update(url: URL, image: UIImage)
}

class CallbackLayer: CALayer {
    
    var onDisplay: () -> Void = {}
    
    override func setNeedsDisplay() {
        super.setNeedsDisplay()
        onDisplay()
    }
}

class GIFAnimationContainer: GIFAnimatable, ImageContainer {
    // MARK: Properties
    var image: UIImage?
    
    lazy var animator: Animator? = Animator(withDelegate: self)
    
    var layer: CALayer = CallbackLayer()
    var frame: CGRect = .zero
    var contentMode: UIView.ContentMode = .scaleAspectFit
    
    var url: URL
    weak var delegate: GIFAnimatableDelegate?
    
    // MARK: Initializer
    init(url: URL, delegate: GIFAnimatableDelegate) {
        self.url = url
        self.delegate = delegate
        
        setupLayerCallback()
        animate(withGIFURL: url)
    }
    
    // MARK: Setup Methods
    private func setupLayerCallback() {
        guard let callbackLayer = layer as? CallbackLayer else {
            return
        }
        callbackLayer.onDisplay = { [weak self] in
            guard let self = self else { return }
            self.updateImageIfNeeded()
            self.delegate?.update(url: self.url, image: self.image ?? UIImage())
        }
    }
    
    // MARK: Animation
    func animate(withGIFURL imageURL: URL, loopCount: Int = 0, preparationBlock: (() -> Void)? = nil, animationBlock: (() -> Void)? = nil, loopBlock: (() -> Void)? = nil) {
        Task(priority: .background) {
            do {
                let (data, _) = try await URLSession.shared.data(from: imageURL)
                await MainActor.run {
                    self.image = UIImage(data: data)
                    self.delegate?.update(url: imageURL, image: self.image ?? UIImage())
                    self.animate(withGIFData: data, loopCount: loopCount, preparationBlock: preparationBlock, animationBlock: animationBlock, loopBlock: loopBlock)
                }
            } catch {
                // Consider a better error handling mechanism here, e.g., delegate method.
                print("Error downloading gif:", error.localizedDescription, "at url:", imageURL.absoluteString)
            }
        }
    }
}


@Observable public class AnimatedImageCache: GIFAnimatableDelegate, ObservableObject {
    
    public static let shared = AnimatedImageCache()
    
    private var containers: [URL: GIFAnimationContainer] = [:]
    private(set) var images: [URL: UIImage] = [:]
    
    public init() {}

    private func register(url: URL?) -> UIImage? {
        guard let url else { return nil }
        if let image = images[url] {
            return image
        }
        if containers[url] == nil {
            containers[url] = GIFAnimationContainer(url: url, delegate: self)
        }
        return images[url]
    }
    
    public func gifImage(for url: URL?) -> Image {
        Image(uiImage: register(url: url) ?? UIImage())
    }
    
    internal func update(url: URL, image: UIImage) {
        images[url] = image
    }
}

public func AsyncAnimatedImage(url: URL?) -> Image {
    AnimatedImageCache.shared.gifImage(for: url)
}
