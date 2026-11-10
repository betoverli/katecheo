#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Native materials for the shell chrome.
/// Liquid Glass (`UIGlassEffect`, prominent glass buttons) is compiled only
/// with the iOS 26 SDK. Older SDKs, and iOS 15–25 at runtime, get classic
/// UIKit blur / filled controls instead.
@interface KCGlassMaterial : NSObject
+ (BOOL)sdkHasLiquidGlass;
+ (nullable UIVisualEffect *)effectWithInteractive:(BOOL)interactive;
+ (void)applyFabStyleToButton:(UIButton *)button;
/// iOS 26 paints a scroll-edge blur on the web view's own scroll view.
/// That view does not scroll (the page scroller does), so the blur would
/// sit on the top and the bottom as a permanent band. Hide it.
+ (void)prepareWebScrollView:(UIScrollView *)scrollView;
@end

NS_ASSUME_NONNULL_END
