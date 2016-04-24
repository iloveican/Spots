import UIKit

public class CollectionAdapter : NSObject {
  var spot: Gridable

  init(spot: Gridable) {
    self.spot = spot
  }
}

extension CollectionAdapter : UIScrollViewDelegate {
  public func scrollViewWillEndDragging(scrollView: UIScrollView, withVelocity velocity: CGPoint, targetContentOffset: UnsafeMutablePointer<CGPoint>) {
    (spot as? CarouselSpot)?.scrollViewWillEndDragging(scrollView, withVelocity: velocity, targetContentOffset: targetContentOffset)
  }
}

extension CollectionAdapter : UICollectionViewDelegate {

  public func collectionView(collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAtIndexPath indexPath: NSIndexPath) -> CGSize {
    return spot.sizeForItemAt(indexPath)
  }

  public func collectionView(collectionView: UICollectionView, didSelectItemAtIndexPath indexPath: NSIndexPath) {
    spot.spotsDelegate?.spotDidSelectItem(spot, item: spot.item(indexPath))
  }

  public func collectionView(collectionView: UICollectionView, canFocusItemAtIndexPath indexPath: NSIndexPath) -> Bool {
    return true
  }

  @available(iOS 9.0, *)
  public func collectionView(collectionView: UICollectionView, shouldUpdateFocusInContext context: UICollectionViewFocusUpdateContext) -> Bool {
    guard let indexPaths = collectionView.indexPathsForSelectedItems() else { return true }
    return indexPaths.isEmpty
  }

  public func collectionView(collectionView: UICollectionView, shouldSelectItemAtIndexPath indexPath: NSIndexPath) -> Bool {
    if let indexPath = collectionView.indexPathsForSelectedItems()?.first {
      collectionView.deselectItemAtIndexPath(indexPath, animated: true)
      return false
    } else {
      return true
    }
  }
}

extension CollectionAdapter : UICollectionViewDataSource  {

  public func collectionView(collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
    return spot.component.items.count
  }

  public func collectionView(collectionView: UICollectionView, cellForItemAtIndexPath indexPath: NSIndexPath) -> UICollectionViewCell {
    spot.component.items[indexPath.item].index = indexPath.item

    let reuseIdentifier = spot.item(indexPath).kind.isPresent ? spot.item(indexPath).kind : spot.component.kind
    let cell = collectionView.dequeueReusableCellWithReuseIdentifier(reuseIdentifier, forIndexPath: indexPath)

    if let cell = cell as? SpotConfigurable {
      cell.configure(&spot.component.items[indexPath.item])
      if spot.component.items[indexPath.item].size.height == 0.0 {
        spot.component.items[indexPath.item].size = cell.size
      }

      spot.configure?(cell)
    }

    collectionView.collectionViewLayout.invalidateLayout()

    return cell
  }
}