#import "CLTwitterCell.h"

@implementation CLTwitterCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier specifier:(PSSpecifier *)specifier
{
    self = [super initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:reuseIdentifier specifier:specifier];

    if (self) {

        self.selectionStyle = UITableViewCellSelectionStyleBlue;
        self.accessoryView = [[UIImageView alloc] initWithFrame:CGRectMake( 0, 0, 38, 38)];

        self.detailTextLabel.numberOfLines = 1;
        self.detailTextLabel.textColor = [UIColor grayColor];

        self.textLabel.textColor = [UIColor blackColor];
        
        if (@available(iOS 13, *)) {
            self.tintColor = [UIColor labelColor];
        }
        else {
            self.tintColor = [UIColor blackColor];
        }

        CGFloat const size = 29.f;

        UIGraphicsBeginImageContextWithOptions(CGSizeMake(size, size), NO, [UIScreen mainScreen].scale);
        specifier.properties[@"iconImage"] = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();

        _avatarView = [[UIView alloc] initWithFrame:self.imageView.bounds];
        _avatarView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _avatarView.backgroundColor = [UIColor colorWithWhite:0.9f alpha:1];
        _avatarView.userInteractionEnabled = NO;
        _avatarView.clipsToBounds = YES;
        _avatarView.layer.cornerRadius = size / 2;
        _avatarView.layer.borderWidth = 2;

        if (@available(iOS 13, *)) {
            _avatarView.layer.borderColor = [[UIColor tertiaryLabelColor] CGColor];
        }
        else {
            _avatarView.layer.borderColor = [[UIColor colorWithWhite:1 alpha:0.3] CGColor];
        }
        
        [self.imageView addSubview:_avatarView];

        _avatarImageView = [[UIImageView alloc] initWithFrame:_avatarView.bounds];
        _avatarImageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _avatarImageView.alpha = 0;
        _avatarImageView.layer.minificationFilter = kCAFilterTrilinear;
        [_avatarView addSubview:_avatarImageView];

        _user = [specifier.properties[@"accountName"] copy];
        NSAssert(_user, @"User name not provided");

        specifier.properties[@"url"] = [self.class _urlForUsername:_user];

        self.detailTextLabel.text = _user;

        if (!_user) {
            return self;
        }

        // self.avatarImage = [UIImage imageNamed:[NSString stringWithFormat:@"/Library/PreferenceBundles/little11prefs.bundle/%@.png", _user]];

        // This has a delay as image needs to be downloaded
        dispatch_async(dispatch_get_global_queue(0,0), ^{
            
            // NSString *size = [UIScreen mainScreen].scale > 2 ? @"original" : @"bigger";
            NSError __block *err = NULL;
            NSData __block *data;
            BOOL __block reqProcessed = false;
            NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"https://pbs.twimg.com/profile_images/1161080936836018176/4GUKuGlb_200x200.jpg"]]];
            
            [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData  *_data, NSURLResponse *_response, NSError *_error) {
                err = _error;
                data = _data;
                reqProcessed = true;
            }] resume];

            while (!reqProcessed) {
                [NSThread sleepForTimeInterval:0];
            }

            if (err)
                return;
                
            dispatch_async(dispatch_get_main_queue(), ^{
                    self.avatarImage = [UIImage imageWithData: data];
            });
        });
    }

    return self;
}

#pragma mark - Avatar

- (void)setAvatarImage:(UIImage *)avatarImage
{
    _avatarImageView.image = avatarImage;

    if (_avatarImageView.alpha == 0)
    {
        [UIView animateWithDuration:0.15
            animations:^{
                _avatarImageView.alpha = 1;
            }
        ];
    }
}

+ (NSURL *)_urlForUsername:(NSString *)user {

    if ([[UIApplication sharedApplication] canOpenURL:[NSURL URLWithString:@"tweetbot://"]]) {
        return [NSURL URLWithString: [@"tweetbot:///user_profile/" stringByAppendingString:user]];
    } else if ([[UIApplication sharedApplication] canOpenURL:[NSURL URLWithString:@"twitterrific://"]]) {
        return [NSURL URLWithString: [@"twitterrific:///profile?screen_name=" stringByAppendingString:user]];
    } else if ([[UIApplication sharedApplication] canOpenURL:[NSURL URLWithString:@"tweetings://"]]) {
        return [NSURL URLWithString: [@"tweetings:///user?screen_name=" stringByAppendingString:user]];
    } else if ([[UIApplication sharedApplication] canOpenURL:[NSURL URLWithString:@"twitter://"]]) {
        return [NSURL URLWithString: [@"twitter://user?screen_name=" stringByAppendingString:user]];
    } else {
        return [NSURL URLWithString: [@"https://mobile.twitter.com/" stringByAppendingString:user]];
    }
}

- (void)setSelected:(BOOL)arg1 animated:(BOOL)arg2
{
    if (arg1) [[UIApplication sharedApplication] openURL:[self.class _urlForUsername:_user] options:@{} completionHandler:nil];
}
@end