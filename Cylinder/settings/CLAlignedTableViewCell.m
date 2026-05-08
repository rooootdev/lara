#import "CLAlignedTableViewCell.h"

#define IMAGE_PADDING 10
#define NUMBER_WIDTH 44
#define NUMBER_PADDING 10

@implementation CLAlignedTableViewCell
@synthesize numberLabel=_numberLabel;

-(id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
    if(self == [super initWithStyle:style reuseIdentifier:reuseIdentifier])
    {
        _numberLabel = [[UILabel alloc] init];
        _numberLabel.font = [_numberLabel.font fontWithSize:16];
        _numberLabel.textColor = [UIColor systemBlueColor];
    }
    return self;
}

- (void) layoutSubviews
{
    [super layoutSubviews];
    CGSize cvs = self.contentView.frame.size;
    CGFloat width = 44; //60;
    self.imageView.frame = CGRectMake(IMAGE_PADDING, IMAGE_PADDING, width - IMAGE_PADDING*2, cvs.height-1 - IMAGE_PADDING*2);
    //self.imageView.contentMode = UIViewContentModeCenter;//|UIViewContentModeScaleAspectFit;


    NSAttributedString *text = [[NSAttributedString alloc] initWithString:self.numberLabel.text  attributes:@{NSFontAttributeName:self.numberLabel.font}];

    CGSize size = 
    // _numberLabel ? [self.numberLabel.text sizeWithFont:self.numberLabel.font
    //                                     constrainedToSize:CGSizeMake(NUMBER_WIDTH,self.textLabel.frame.size.height)
    //                                         lineBreakMode:self.numberLabel.lineBreakMode] : CGSizeZero;

    _numberLabel ? [text boundingRectWithSize:CGSizeMake(NUMBER_WIDTH,self.textLabel.frame.size.height) options:NSStringDrawingUsesLineFragmentOrigin context:nil].size : CGSizeZero;

    size.width += NUMBER_PADDING;

    self.numberLabel.frame = CGRectMake(
            cvs.width - size.width,
            self.textLabel.frame.origin.y,
            size.width,
            self.textLabel.frame.size.height);

    self.textLabel.frame = CGRectMake(width,
                              self.textLabel.frame.origin.y,
                              cvs.width - width*2 - size.width,
                              self.textLabel.frame.size.height);

    self.detailTextLabel.frame = CGRectMake(width,
                       self.detailTextLabel.frame.origin.y,
                       cvs.width - width*2,
                       self.detailTextLabel.frame.size.height);
    [self addSubview:self.numberLabel];
}
@end
