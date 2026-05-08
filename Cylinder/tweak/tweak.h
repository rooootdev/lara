
#import "CALayer+Cylinder.h"
#import "CylinderAnimator.h"

@interface SBIconScrollView : UIScrollView
@end 

@interface SBFolder : NSObject
@property (nonatomic, assign, readonly) NSUInteger listCount;
@end

@interface SBRootFolder : SBFolder
@end

@interface SBIconController : UIViewController
+ (id)sharedInstance;
@property (nonatomic, assign, readonly) SBRootFolder *rootFolder;
@end

@interface SBFolderView : UIView 
@property (assign,getter=isRotating,nonatomic) BOOL rotating;
@property (nonatomic,copy,readonly) NSArray * iconListViews API_AVAILABLE(ios(7.0));

- (void)enumerateIconListViewsUsingBlock:(void(^)())block;
@end 
