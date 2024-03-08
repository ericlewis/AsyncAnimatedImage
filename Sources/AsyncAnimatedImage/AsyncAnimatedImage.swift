import SwiftUI

protocol GIFAnimatableDelegate: AnyObject {
    func update(url: URL, imageHash: Int)
}

class GIFAnimationContainer: _GIFAnimatable {
    
    // MARK: Properties
    var image: UIImage?
    
    lazy var animator: _Animator? = _Animator(withDelegate: self)
    
    var url: URL
    var task: Task<Void, Never>?
    weak var delegate: GIFAnimatableDelegate?
    
    // MARK: Initializer
    init(url: URL, delegate: GIFAnimatableDelegate) {
        self.url = url
        self.delegate = delegate
        
        animate(withGIFURL: url)
    }
    
    func animatorHasNewFrame() {
        self.image = animator?.activeFrame()
        self.delegate?.update(url: self.url, imageHash: self.image.hashValue ?? 0)
    }
    
    // MARK: Animation
    func animate(withGIFURL imageURL: URL, loopCount: Int = 0, preparationBlock: (() -> Void)? = nil, animationBlock: (() -> Void)? = nil, loopBlock: (() -> Void)? = nil) {
        self.task?.cancel()
        self.task = Task(priority: .background) {
            do {
                let (data, _) = try await URLSession.shared.data(from: imageURL)
                try Task.checkCancellation()
                let image = UIImage(data: data)
                await MainActor.run {
                    self.image = image
                    self.delegate?.update(url: imageURL, imageHash: self.image.hashValue ?? 0)
                    self.animator?.animate(withGIFData: data, size: .zero, contentMode: .center, loopCount: loopCount, preparationBlock: preparationBlock, animationBlock: animationBlock, loopBlock: loopBlock)
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
