#import "LiquidGlassMaterial.h"

@implementation KCGlassMaterial

+ (BOOL)sdkHasLiquidGlass {
#if defined(__IPHONE_26_0)
    if (@available(iOS 26.0, *)) {
        return YES;
    }
#endif
    return NO;
}

+ (UIVisualEffect *)effectWithInteractive:(BOOL)interactive {
#if defined(__IPHONE_26_0)
    if (@available(iOS 26.0, *)) {
        UIGlassEffect *glass = nil;
        SEL effectSelector = NSSelectorFromString(@"effectWithStyle:");
        if ([[UIGlassEffect class] respondsToSelector:effectSelector]) {
            glass = [UIGlassEffect effectWithStyle:UIGlassEffectStyleRegular];
        } else {
            glass = [UIGlassEffect new];
        }
        glass.interactive = interactive;
        return glass;
    }
#endif
    return [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemChromeMaterial];
}

+ (void)prepareWebScrollView:(UIScrollView *)scrollView {
#if defined(__IPHONE_26_0)
    if (@available(iOS 26.0, *)) {
        scrollView.topEdgeEffect.hidden = YES;
        scrollView.bottomEdgeEffect.hidden = YES;
        scrollView.leftEdgeEffect.hidden = YES;
        scrollView.rightEdgeEffect.hidden = YES;
    }
#else
    (void)scrollView;
#endif
}

+ (void)applyFabStyleToButton:(UIButton *)button {
    UIImageSymbolConfiguration *icon = [UIImageSymbolConfiguration configurationWithPointSize:22 weight:UIImageSymbolWeightSemibold];
    UIImage *plus = [UIImage systemImageNamed:@"plus" withConfiguration:icon];
    UIButtonConfiguration *configuration = nil;
#if defined(__IPHONE_26_0)
    if (@available(iOS 26.0, *)) {
        configuration = [UIButtonConfiguration prominentGlassButtonConfiguration];
        configuration.baseForegroundColor = UIColor.whiteColor;
    }
#endif
    if (configuration == nil) {
        configuration = [UIButtonConfiguration filledButtonConfiguration];
        // Warm notebook accent (matches KCDesign.accent light).
        configuration.baseBackgroundColor = [UIColor colorWithRed:(176.0 / 255.0) green:(122.0 / 255.0) blue:(69.0 / 255.0) alpha:1];
        configuration.baseForegroundColor = UIColor.whiteColor;
        configuration.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
    }
    configuration.image = plus;
    configuration.contentInsets = NSDirectionalEdgeInsetsZero;
    button.configuration = configuration;
}

@end
