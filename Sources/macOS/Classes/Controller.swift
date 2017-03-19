import Cocoa

public enum ControllerBackground {
  case regular, dynamic
}

open class Controller: NSViewController, SpotsProtocol {

  /// A closure that is called when the controller is reloaded with components
  public static var componentsDidReloadComponentModels: ((Controller) -> Void)?

  open static var configure: ((_ container: SpotsScrollView) -> Void)?

  /// A collection of CoreComponent objects
  open var components: [Component] {
    didSet {
      components.forEach { $0.delegate = delegate }
      delegate?.componentsDidChange(components)
    }
  }

  public var contentView: View {
    return view
  }

  /// An array of refresh positions to avoid refreshing multiple times when using infinite scrolling
  open var refreshPositions = [CGFloat]()

  /// An optional StateCache used for view controller caching
  open var stateCache: StateCache?

  #if DEVMODE
  /// A dispatch queue is a lightweight object to which your application submits blocks for subsequent execution.
  public let fileQueue: DispatchQueue = DispatchQueue.global(qos: DispatchQoS.QoSClass.default)
  /// An identifier for the type system object being monitored by a dispatch source.
  public var source: DispatchSourceFileSystemObject?
  #endif

  /// A delegate for when an item is tapped within a Spot
  weak public var delegate: ComponentDelegate? {
    didSet {
      components.forEach {
        $0.delegate = delegate
      }
      delegate?.componentsDidChange(components)
    }
  }

  /// A custom scroll view that handles the scrolling for all internal scroll views
  public var scrollView: SpotsScrollView = SpotsScrollView()

  /// A scroll delegate for handling didReachBeginning and didReachEnd
  weak open var scrollDelegate: ScrollDelegate?

  /// A bool value to indicate if the Controller is refeshing
  open var refreshing = false

  fileprivate let backgroundType: ControllerBackground

  /**
   - parameter components: An array of CoreComponent objects
   - parameter backgroundType: The type of background that the Controller should use, .Regular or .Dynamic
   */
  public required init(components: [Component] = [], backgroundType: ControllerBackground = .regular) {
    self.components = components
    self.backgroundType = backgroundType
    super.init(nibName: nil, bundle: nil)!

    NotificationCenter.default.addObserver(self, selector: #selector(Controller.scrollViewDidScroll(_:)), name: NSNotification.Name.NSScrollViewDidLiveScroll, object: scrollView)

    NotificationCenter.default.addObserver(self, selector: #selector(windowDidResize(_:)), name: NSNotification.Name.NSWindowDidResize, object: nil)

    NotificationCenter.default.addObserver(self, selector: #selector(windowDidEndLiveResize(_:)), name: NSNotification.Name.NSWindowDidEndLiveResize, object: nil)
  }

  /**
   - parameter cacheKey: A key that will be used to identify the StateCache
   */
  public convenience init(cacheKey: String) {
    let stateCache = StateCache(key: cacheKey)
    self.init(components: Parser.parse(stateCache.load()))
    self.stateCache = stateCache
  }

  /**
   - parameter component: A Component object
   */
  public convenience init(component: Component) {
    self.init(components: [component])
  }

  /**
   - parameter json: A JSON dictionary that gets parsed into UI elements
   */
  public convenience init(_ json: [String : Any]) {
    self.init(components: Parser.parse(json))
  }

  /**
   deinit
   */
  deinit {
    NotificationCenter.default.removeObserver(self)
    components.forEach { $0.delegate = nil }
    delegate = nil
    scrollDelegate = nil
  }

  /**
   Returns an object initialized from data in a given unarchiver

   - parameter coder: An unarchiver object.
   */
  public required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  /// A look up method for resolving a component at index as a CoreComponent object.
  ///
  /// - parameter index: The index of the component that you are trying to resolve.
  ///
  /// - returns: An optional CoreComponent object.
  open func component(at index: Int = 0) -> Component? {
    return components.filter({ $0.index == index }).first
  }

  /**
   A generic look up method for resolving components using a closure

   - parameter closure: A closure to perform actions on a component

   - returns: An optional CoreComponent object
   */
  public func resolve(component closure: (_ index: Int, _ component: Component) -> Bool) -> Component? {
    for (index, component) in components.enumerated()
      where closure(index, component) {
        return component
    }
    return nil
  }

  /**
   Instantiates a view from a nib file and sets the value of the view property.
   */
  open override func loadView() {
    let view: NSView

    switch backgroundType {
    case .regular:
      view = NSView()
    case .dynamic:
      let visualEffectView = NSVisualEffectView()
      visualEffectView.blendingMode = .behindWindow
      view = visualEffectView
    }

    view.autoresizingMask = .viewWidthSizable
    view.autoresizesSubviews = true
    self.view = view
  }

  /**
   Called after the view controller’s view has been loaded into memory.
   */
  open override func viewDidLoad() {
    super.viewDidLoad()

    view.addSubview(scrollView)
    scrollView.hasVerticalScroller = true
    scrollView.autoresizingMask = [.viewWidthSizable, .viewHeightSizable]

    setupComponents()
    Controller.configure?(scrollView)
  }

  open override func viewDidAppear() {
    super.viewDidAppear()

    for component in components {
      component.layout(scrollView.frame.size)
    }
  }

  public func reloadSpots(components: [Component], closure: (() -> Void)?) {
    for component in self.components {
      component.delegate = nil
      component.view.removeFromSuperview()
    }
    self.components = components
    delegate = nil

    setupComponents()
    closure?()
    scrollView.layoutSubviews()
  }

  /**
   - parameter animated: An optional animation closure that runs when a component is being rendered
   */
  public func setupComponents(animated: ((_ view: View) -> Void)? = nil) {
    components.enumerated().forEach { index, component in
      setupComponent(at: index, component: component)
      animated?(component.view)
    }
  }

  public func setupComponent(at index: Int, component: Component) {
    if component.view.superview == nil {
      scrollView.componentsView.addSubview(component.view)
    }

    components[index].model.index = index
    component.registerAndPrepare()

    var height = component.computedHeight
    if let componentSize = component.model.size, componentSize.height > height {
      height = componentSize.height
    }

    component.setup(CGSize(width: view.frame.width, height: height))
    component.model.size = CGSize(
      width: view.frame.width,
      height: ceil(component.view.frame.height))
  }

  open override func viewDidLayout() {
    super.viewDidLayout()

    for component in components {
      component.layout(CGSize(width: view.frame.width,
        height: component.computedHeight))

      for compositeComponent in component.compositeComponents {
        compositeComponent.component.setup(CGSize(width: view.frame.width,
                                        height: compositeComponent.component.computedHeight))
      }
    }
  }

  public func deselectAllExcept(selectedComponent: Component) {
    for component in components {
      if selectedComponent.view != component.view {
        component.deselect()
      }
    }
  }

  public func windowDidResize(_ notification: Notification) {
    components.forEach { component in
      layoutComponent(component)
    }
    scrollView.layoutSubviews()
  }

  public func windowDidEndLiveResize(_ notification: Notification) {
    components.forEach { component in
      layoutComponent(component)
    }
  }

  fileprivate func layoutComponent(_ component: Component) {
    if component.userInterface is CollectionView {
      guard let layout = component.model.layout, layout.span >= 1 else {
        return
      }

      component.setup(component.view.frame.size)
    } else if component.userInterface is TableView {
      let size = CGSize(width: view.frame.size.width, height: component.view.frame.size.height)
      component.layout(size)
    }
  }

  open func scrollViewDidScroll(_ notification: NSNotification) {
    guard let scrollView = notification.object as? SpotsScrollView,
      let delegate = scrollDelegate,
      let _ = NSApplication.shared().mainWindow, !refreshing && scrollView.contentOffset.y > 0
      else {
        return
    }

    let offset = scrollView.contentOffset
    let totalHeight = scrollView.documentView?.frame.size.height ?? 0
    let multiplier: CGFloat = !refreshPositions.isEmpty
      ? CGFloat(1 + refreshPositions.count)
      : 1.5
    let currentOffset = offset.y + scrollView.frame.size.height
    let shouldFetch = currentOffset > totalHeight - scrollView.frame.size.height * multiplier + scrollView.frame.origin.y &&
      !refreshPositions.contains(currentOffset)

    // Scroll did reach top
    if scrollView.contentOffset.y < 0 &&
      !refreshing {
      refreshing = true
      delegate.didReachBeginning(in: scrollView) {
        self.refreshing = false
      }
    }

    if shouldFetch {
      // Infinite scrolling
      refreshing = true
      refreshPositions.append(currentOffset)
      delegate.didReachEnd(in: scrollView) {
        self.refreshing = false
      }
    }
  }
}
