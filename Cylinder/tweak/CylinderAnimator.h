#import <UIKit/UIKit.h>

typedef void (*ObjcMsgSendType)(_Nonnull id, _Nonnull SEL, UIView * _Nonnull, CGFloat);


NS_ASSUME_NONNULL_BEGIN

@interface CylinderAnimator : NSObject

@property (nonatomic, assign) bool enabled;

-(instancetype)initWithMsgSend:(ObjcMsgSendType)msgSend;
-(void)reloadPrefs;
- (void)manipulate:(nonnull UIView *)view offset:(CGFloat)offset rand:(uint32_t)rand;

@end

@interface SBIcon : NSObject
@property (nonatomic,copy,readonly) NSString * displayName; 
@end 

@interface SBIconImageView : UIView
@end 

@interface SBIconImageCrossfadeView : UIView
@end 

@interface SBIconView : UIView {
    SBIconImageView* _iconImageView;
    SBIconImageCrossfadeView* _crossfadeView;
}

@property (nonatomic,retain) SBIcon *icon;
@end 


NS_CLASS_AVAILABLE_IOS(4_0) @interface SBIconListView : UIView
@property(readonly, nonatomic) NSUInteger maximumIconCount;
@property(readonly, nonatomic) NSUInteger maxIcons API_DEPRECATED_WITH_REPLACEMENT("maximumIconCount", ios(4.0, 13.0));
@property(readonly, nonatomic) NSUInteger iconColumnsForCurrentOrientation;
@property(readonly, nonatomic) NSUInteger iconRowsForCurrentOrientation;
@property (assign, nonatomic) BOOL wasModifiedByCylinder;

-(NSArray *)icons;
-(void)layoutIconsNow;
- (void)setIconsNeedLayout;
- (void)setAlphaForAllIcons:(CGFloat)alpha;
- (void)enumerateIconViewsUsingBlock:(void (^)(SBIconView* icon, NSUInteger idx, BOOL *stop))block;

@end
NS_ASSUME_NONNULL_END