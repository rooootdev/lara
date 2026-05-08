/*
Copyright (C) 2014 Reed Weichler

This file is part of Cylinder.

Cylinder is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

Cylinder is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with Cylinder.  If not, see <http://www.gnu.org/licenses/>.
*/

#import <UIKit/UIKit.h>
#import "CLAlignedTableViewCell.h"

@interface CLEffect : NSObject

@property (nonatomic, assign) CLAlignedTableViewCell *cell;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *selectorName;
@property (nonatomic, copy) NSString *developer;
@property (nonatomic, assign, getter=isSelected) BOOL selected;

- (id)initWithName:(NSString*)name selectorName:(NSString *)selectorName developer:(NSString *)developer;

@end
