import SwiftUI

protocol GIFAnimatableDelegate: AnyObject {
    func update(url: URL, imageHash: Int)
}

class GIFAnimationContainer: _GIFAnimatable {
    
    // MARK: Properties
    var image: UIImage?
    
    lazy var animator: _Animator = _Animator(withDelegate: self)
    
    var url: URL
    var size: CGSize
    var task: Task<Void, Never>?
    weak var delegate: GIFAnimatableDelegate!
    
    // MARK: Initializer
    init(url: URL, size: CGSize, delegate: GIFAnimatableDelegate) {
        self.url = url
        self.delegate = delegate
        self.size = size
        animate(withGIFURL: url)
    }
    
    func animatorHasNewFrame() {
        guard let frame = animator.activeFrame() else { return }
        self.image = frame
        self.delegate.update(url: self.url, imageHash: frame.hashValue)
    }
    
    // MARK: Animation
    func animate(withGIFURL imageURL: URL, loopCount: Int = 0, preparationBlock: (() -> Void)? = nil, animationBlock: (() -> Void)? = nil, loopBlock: (() -> Void)? = nil) {
        self.task?.cancel()
        self.task = Task(priority: .background) {
            do {
                let (data, _) = try await URLSession.shared.data(from: imageURL)
                try Task.checkCancellation()
                let image = size == .zero ? UIImage(data: data) : UIImage(data: data)?.resized(to: size)
                self.image = image
                self.delegate.update(url: imageURL, imageHash: image?.hashValue ?? 0)
                self.animator.animate(withGIFData: data, size: size, contentMode: .center, loopCount: loopCount, preparationBlock: preparationBlock, animationBlock: animationBlock, loopBlock: loopBlock)
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


@Observable public class AnimatedImageCache: GIFAnimatableDelegate {
    
    public static let shared = AnimatedImageCache()
    private static let placeholder: UIImage = .init()
    
    private var containers: NSCache<NSURL, GIFAnimationContainer> = .init()
    
    var imageHashes: [URL: Int] = [:]
    
    public init() {}
    
    private func register(url: URL?, size: CGSize) -> UIImage? {
        guard let url else { return nil }
        if containers.object(forKey: url as NSURL) == nil {
            containers.setObject(GIFAnimationContainer(url: url, size: size, delegate: self), forKey: url as NSURL)
        }
        let _ = imageHashes[url]
        return containers.object(forKey: url as NSURL)?.image
    }
    
    public func gifImage(for url: URL?, size: CGSize = .zero) -> Image {
        Image(uiImage: register(url: url, size: size) ?? Self.placeholder)
    }
    
    @MainActor
    internal func update(url: URL, imageHash: Int) {
        imageHashes[url] = imageHash
    }
    
    public func flush() {
        containers.removeAllObjects()
    }
}

public func AsyncAnimatedImage(url: URL?, size: CGSize = .zero) -> Image {
    AnimatedImageCache.shared.gifImage(for: url, size: size)
}
