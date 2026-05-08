#import <UIKit/UIKit.h>
#import <Preferences/PSSpecifier.h>
#import <Preferences/PSTableCell.h>

@interface CLTwitterCell : PSTableCell{
    NSString *_user;
}
@property (nonatomic, retain, readonly) UIView *avatarView;
@property (nonatomic, retain, readonly) UIImageView *avatarImageView;
@end
