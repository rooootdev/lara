#import "CLEffect.h"
#import "../Defines.h"

@implementation CLEffect
@synthesize name=_name, selectorName=_selectorName, developer=_developer, selected=_selected, cell=_cell;

- (id)initWithName:(NSString*)name selectorName:(NSString *)selectorName developer:(NSString *)developer  {
	if (self = [super init]) {
		self.name = name;
		self.selectorName = selectorName;
		self.developer = developer;
	}
	return self;
}

@end
