#import "CALayer+Cylinder.h"
#import <objc/runtime.h>

@implementation CALayer(Cylinder)
-(void)setSavedValue:(NSValue *)value
{
    objc_setAssociatedObject(self, @selector(savedValue), value, OBJC_ASSOCIATION_RETAIN);
}
-(NSValue *)savedValue
{
    return objc_getAssociatedObject(self, @selector(savedValue));
}
-(void)savePosition
{
    if(!self.savedValue)
        self.savedValue = [NSValue valueWithCGPoint:self.position];

}
-(void)restorePosition
{
    NSValue *value = self.savedValue;
    if(!value) return;

    self.position = value.CGPointValue;
    self.savedValue = nil;
}

@end
