import SwiftUI
import Gifu

protocol GIFAnimatableDelegate: AnyObject {
    func update(url: URL, imageHash: Int)
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
    var task: Task<Void, Never>?
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
            self.delegate?.update(url: self.url, imageHash: self.image.hashValue ?? 0)
        }
    }
    
    // MARK: Animation
    func animate(withGIFURL imageURL: URL, loopCount: Int = 0, preparationBlock: (() -> Void)? = nil, animationBlock: (() -> Void)? = nil, loopBlock: (() -> Void)? = nil) {
        self.task = Task(priority: .background) {
            do {
                let (data, _) = try await URLSession.shared.data(from: imageURL)
                try Task.checkCancellation()
                await MainActor.run {
                    self.image = UIImage(data: data)
                    self.delegate?.update(url: imageURL, imageHash: self.image.hashValue ?? 0)
                    self.animate(withGIFData: data, loopCount: loopCount, preparationBlock: preparationBlock, animationBlock: animationBlock, loopBlock: loopBlock)
                }
            } catch {
                // Consider a better error handling mechanism here, e.g., delegate method.
                print("Error downloading gif:", error.localizedDescription, "at url:", imageURL.absoluteString)
            }
        }
    }
    
    deinit {
        self.task?.cancel()
    }
}


@Observable public class AnimatedImageCache: GIFAnimatableDelegate, ObservableObject {
    
    public static let shared = AnimatedImageCache()
    
    private var containers: NSCache<NSURL, GIFAnimationContainer> = .init()
    
    var imageHashes: [URL: Int] = [:]
    
    public init() {}

    private func register(url: URL?) -> UIImage? {
        guard let url else { return nil }
        if containers.object(forKey: url as NSURL) == nil {
            containers.setObject(GIFAnimationContainer(url: url, delegate: self), forKey: url as NSURL)
        }
        let _ = imageHashes[url]
        return containers.object(forKey: url as NSURL)?.image
    }
    
    public func gifImage(for url: URL?) -> Image {
        Image(uiImage: register(url: url) ?? UIImage())
    }
    
    internal func update(url: URL, imageHash: Int) {
        imageHashes[url] = imageHash
    }
}

public func AsyncAnimatedImage(url: URL?) -> Image {
    AnimatedImageCache.shared.gifImage(for: url)
}
