//
//  CylinderAnimator.swift
//  Cask
//
//  Created by Ryan Nair on 2/16/24.
//

import UIKit

private extension UIView {

    static let perspectiveDistance = (UIScreen.main.bounds.size.width + UIScreen.main.bounds.size.height) / 2

    func rotate(_ angle: CGFloat) {
        layer.transform = CATransform3DRotate(layer.transform, angle, 0, 0, 1)
    }

    func rotate(_ angle: CGFloat, _ pitch: CGFloat, _ yaw: CGFloat, _ roll: CGFloat = 1) {
        var transform = layer.transform

        if !pitch.isZero || !yaw.isZero {
            transform.m34 = -1/UIView.perspectiveDistance
        }

        layer.transform = CATransform3DRotate(transform, angle, pitch, yaw, roll)
    }

    func scale(_ percent: CGFloat) {
        var transform = layer.transform
        
        let oldm34 = transform.m34
        transform.m34 = -1/UIView.perspectiveDistance
        transform = CATransform3DScale(transform, percent, percent, 1)
        transform.m34 = oldm34

        layer.transform = transform
    }

    func translate(_ x: CGFloat, _ y: CGFloat) {
        layer.transform = CATransform3DTranslate(layer.transform, x, y, 0)
    }

    func translate(_ x: CGFloat, _ y: CGFloat, _ z: CGFloat) {
        var transform = layer.transform

        let oldm34 = transform.m34
        transform.m34 = -1/UIView.perspectiveDistance
        transform = CATransform3DTranslate(transform, x, y, z)
        transform.m34 = oldm34

        layer.transform = transform
    }

    var width: CGFloat {
        return frame.size.width / layer.transform.m11
    }
     
    var height: CGFloat {
        return frame.size.height / layer.transform.m22
    }
}

@objc @implementation extension CylinderAnimator { 
    
    final private lazy var screenWidth: CGFloat = {
        return UIScreen.main.bounds.size.width
    }()

    final private lazy var screenHeight: CGFloat = {
        return UIScreen.main.bounds.size.height
    }()
    
    var enabled: Bool = false

    final private var msgSend: ObjcMsgSendType
    final private var scriptSelectors: [Selector] = []
    final private var scriptCount: UInt32 = 0
    final private var randomize: Bool = false

    init(msgSend: ObjcMsgSendType) {
        self.msgSend = msgSend
        super.init()
        reloadPrefs()
    }

    func reloadPrefs() {
        let settings = UserDefaults(suiteName: "com.ryannair05.cylinderremade")
        settings?.register(defaults: [
            "enabled": true,
            "randomized": false,
            "effect": [["effect": "Cube (inside)", "effectSelector": "cubeInside"]]
        ])

        enabled = settings?.bool(forKey: "enabled") ?? true
        randomize = settings?.bool(forKey: "randomized") ?? false

        if !enabled {
            scriptSelectors.removeAll()
            return
        }

        if let scripts = settings?.array(forKey: "effect") as? [[String: String]] {
            scriptSelectors.removeAll(keepingCapacity: true)

            scriptSelectors = scripts.compactMap { scriptDict in
                if let script = scriptDict["effectSelector"] {
                    return Selector("\(script)::")
                }
                return nil
            }

            scriptCount = UInt32(scriptSelectors.count)
        }
    }

    func manipulate(_ view: UIView, offset: CGFloat, rand: UInt32) {
        if randomize {
            let scriptSelector = scriptSelectors[Int(rand % scriptCount)]
            self.msgSend(self, scriptSelector, view, offset)
        } else {
            for selector in scriptSelectors {
                self.msgSend(self, selector, view, offset)
            }
        }
    }

    private func backwards(_ page: UIView, _ offset: CGFloat) {
        page.translate(2*offset, 0)
    }

    private func cardHorizontal(_ page: UIView, _ offset: CGFloat) {
        page.layer.savePosition()
        page.layer.position.x += offset

        let percent = offset/page.width
        
        if abs(percent) >= 0.5 {
            page.alpha = 0
        }
        
        page.rotate(-.pi * percent, 0, 1, 0)
    }

    private func cardVertical(_ page: UIView, _ offset: CGFloat) {
        page.layer.savePosition()
        page.layer.position.x += offset

        let percent = offset/page.width
        
        if abs(percent) >= 0.5 {
            page.alpha = 0
        }
        
        page.rotate(.pi * percent, 1, 0, 0)
    }
    
    private func chomp(_ page: UIView, _ offset: CGFloat) {
        var percent = offset/page.width
        
        if percent < 0 {
            percent = -percent
        }
        
        percent *= screenHeight/2
        
        for icon in page.subviews {
            if icon.frame.midY < page.width/2 {
                page.translate(0, -percent)
            }
            else {
                page.translate(0, percent)
            }
        }
    }
    
    private func cubeInside(_ page: UIView, _ offset: CGFloat) {
        let percent = offset/page.width
        page.layer.savePosition()
        page.layer.position.x += offset
        
        let angle = percent * .pi/2
        
        let h = page.width/2
        var x = h*cos(abs(angle)) - h
        let z = h*sin(abs(angle))
        
        if percent > 0 {
            x = -x
        }
        
        x -= offset
        
        page.translate(x, 0, z)
        page.rotate(angle, 0, 1, 0)
    }
    
    private func cubeOutside(_ page: UIView, _ offset: CGFloat) {
        let percent = offset/page.width
        page.layer.savePosition()
        page.layer.position.x += offset
        
        var angle = -percent * .pi/2
        
        let h = page.width/2
        var x = h*cos(abs(angle)) - h
        let z = -h*sin(abs(angle))
        
        if percent > 0 {
            x = -x
        }
        
        x -= offset
        
        page.translate(x, 0, z)
        page.rotate(angle, 0, 1, 0)

        let threshold = abs(atan((UIView.perspectiveDistance - z)/x))
        angle = abs(angle)
        
        if angle > threshold {
            page.alpha = 1 - (angle - threshold)/(CGFloat.pi/2 - threshold)
        }
        else {
            page.alpha = 1
        }
    }

    private func doubleDoor(_ page: UIView, _ offset: CGFloat) {
        page.translate(offset, 0)
        
        let percent = abs(offset/page.width)
        
        for icon in page.subviews {
            if icon.frame.midX > page.width/2 {
                icon.translate(percent*page.width, 0)
            }
            else {
                icon.translate(-percent*page.width, 0)
            }
        }
    }

    private func doubleHelix(_ page: SBIconListView, _ offset: CGFloat) {
        let pageWidth = page.width
        let pageHeight = page.height
        let maxColumns = CGFloat(page.iconColumnsForCurrentOrientation)
        let percent = abs(offset / pageWidth)
        let ops = offset / pageWidth
        let midx = pageWidth / 2
        let midy = pageHeight / 2 + 7
        let fx = min(max(percent * 5, -1), 1)
        let pc = percent + 0.0001 // Prevent division by zero

        page.enumerateIconViews { icon, i, _ in
            let iconFrame = icon.center
            let icx = iconFrame.x
            let icy = iconFrame.y
            let ox = midx - icx
            let oy = midy - icy

            // Calculate the new position
            let nx = midx - ops / pc * (pageWidth / (7.5 - maxColumns)) *
                sin(ops * 4 * .pi + 8 * (oy - (1 / maxColumns * ox)) / 1.33 / pageHeight)
            let ny = midy - oy + (1 / maxColumns) * ox

            // Prevent overlapping by slightly adjusting positions based on index
            let offsetVal = CGFloat(i + 1) * 0.1
            let finalNx = nx + offsetVal
            let finalNy = ny + offsetVal

            // Calculate translation and rotation
            let translateX = fx * (finalNx - icx)
            let translateY = fx * (finalNy - icy)
            let rotateAngle = fx * (ops * 4 * .pi + 0.5 * ops / pc * .pi +
                8 * (oy - (1 / maxColumns * ox)) / 1.33 / pageHeight)

            icon.translate(translateX, translateY, 0)
            icon.rotate(rotateAngle, 0, 1, 0)
        }
    }

    private func hinge(_ page: UIView, _ offset: CGFloat) {
        let percent = offset/page.width
        page.layer.savePosition()
        page.layer.position.x += offset
        
        let angle = percent * .pi
        var x = page.width/2
        if percent > 0 {
            x = -x
        }
        
        page.translate(x, 0)
        page.rotate(angle, 0, 1, 0)
        page.translate(-x, 0)
    }

    private func horizontalAntLines(_ page: UIView, _ offset: CGFloat) {
         let percent = offset/page.width
         
         page.translate(offset, 0)
         page.alpha = 1 - abs(percent)
         
         var direction: CGFloat = 1
         var lastY: CGFloat = 0
         
         for icon in page.subviews {
             if icon.frame.origin.y > lastY  {
                 direction = -direction
                 lastY = icon.frame.origin.y
             }
             icon.translate(direction*offset, 0)
         }
     }

    private func hyperspace(_ page: SBIconListView, _ offset: CGFloat) {
        let percent = abs(offset/page.width)
        let rollup = min(percent * 5, 1)
        let front: CGFloat = (offset > 0) ? 1 : -1
        let runaway = max(min((percent-0.2)/0.7, 1), 0)
        
        let middleX = page.width/2
        let middleY = page.height/2 + 7

        page.enumerateIconViews { icon, _ , _ in
            let iconX = icon.frame.midX
            let iconY = icon.frame.midY

            let angle = atan((middleY-iconY)/(middleX-iconX))
            let side: CGFloat = (middleX < iconX) ? -1 : 1
            let pitch = CGFloat.pi/2.4

            if abs(angle) == CGFloat.pi/2 {
                let side2: CGFloat = (middleX-iconY > 0) ? -1 : 1
                icon.rotate(rollup*pitch*side2, 1, 0)
                icon.translate(-500*runaway*side2*front, 0)
            }
            else {
                icon.rotate(rollup*angle)
            }
            icon.rotate(rollup*pitch*side, 0, 1, 0)
            icon.translate(500*runaway*side*front, 0)
            icon.alpha = 1 - runaway
        }

        page.translate(offset, 0)
    }

    private func leftStairs(_ page: UIView, _ offset: CGFloat) {
        let percent = offset/page.width
        let x = percent * -20
        let z = percent * -100
        
        page.translate(x, 0, z)
    }

    private func iconCollection(_ page: SBIconListView, _ offset: CGFloat) {
        let percent = abs(offset/page.width)
        let centerX = page.width/2
        let centerY = page.height/2

        page.enumerateIconViews { icon, _ , _ in
            let x = icon.frame.midX
            let y = icon.frame.midY
            
            var hypotenuse = percent*hypot(x-centerX, y-centerY)
            let angle = atan((centerX - x) / (centerY - y))
            if y > centerY {
                hypotenuse = -hypotenuse
            }
            
            let dx = hypotenuse * sin(angle)
            let dy = hypotenuse * cos(angle)
            
            icon.translate(dx, dy)
        }
    }
    
    private func pageFade(_ page: UIView, _ offset: CGFloat) {
        let percent = 1 - abs(offset/page.layer.bounds.size.width)
        
        page.alpha = percent
        
        for icon in page.subviews {
            icon.alpha = percent
        }
    }

    private func pageFlip(_ page: UIView, _ offset: CGFloat) {
        let percent = offset/page.width
        
        let angle = percent * .pi
        
        page.alpha = 1 - abs(percent)
        page.rotate(angle, 0, 1, 0)
    }

    private func pageTwist(_ page: UIView, _ offset: CGFloat) {
        let percent = offset/page.width
        
        let angle = percent * .pi
        
        page.alpha = 1 - abs(percent)
        page.rotate(-2/3*angle, 1, 0, 0)
    }

    private func psychospiral(_ page: SBIconListView, _ offset: CGFloat) {
        let percent = abs(offset/page.layer.bounds.size.width)
        let side: CGFloat = (offset > 0) ? 1 : -1

        let rollup = min(percent*5, 1)
        let runaway = max(min((percent-0.20)/0.6, 1), 0)

        let middleX = page.width/2
        let middleY = page.height/2 + 7
        let radiusParts = middleY / CGFloat(page.subviews.count)
        let theta = (3.5*CGFloat.pi) / CGFloat(page.subviews.count)

        page.enumerateIconViews { icon, i , _ in
            let initAngle = CGFloat(i) * theta
            let initRadius = CGFloat(i) * radiusParts
            let angle = initAngle+runaway*(3.5*CGFloat.pi-initAngle)
            let radius = initRadius+runaway*(middleY-initRadius) + 45
            let iconX = icon.frame.midX
            let iconY = icon.frame.midY
            let pathX = middleX + (radius*cos(angle)) * side
            let pathY = middleY + (radius*sin(angle)) * side

            icon.translate(rollup*(pathX-iconX), rollup*(pathY-iconY))
            icon.rotate(rollup * angle)
            let size = min(1-(1-(radius/(middleY+50)))*rollup, 1)
            icon.scale(size*size)
        }

        page.translate(offset, 0)
    }
    
    private func rightStairs(_ page: UIView, _ offset: CGFloat) {
        let percent = offset/page.width
        let x = percent * -20
        let z = percent * 100
        
        page.translate(x, 0, z)
    }
    
    private func scatter(_ page: SBIconListView, _ offset: CGFloat) {
        let percent = abs(offset/page.width)

        page.enumerateIconViews { icon, i , _ in
            if i % 2 == 1 {
                icon.translate(0, percent*page.height/2)
            }
            else {
                icon.translate(0, -percent*page.height/2)
            }
        }
    }

    private func shrink(_ page: UIView, _ offset: CGFloat) {
        let percent = 1 - abs(offset/page.layer.bounds.size.width)
        
        for icon in page.subviews {
            icon.scale(percent)
        }
    }
    
    private func spin(_ page: UIView, _ offset: CGFloat) {
        let percent = offset/page.width
        let angle = percent * .pi * 2
        
        for icon in page.subviews {
            icon.rotate(angle)
        }
    }
    
    private func suck(_ page: UIView, _ offset: CGFloat) {
        let percent = offset/page.width
        let fixed = abs(percent)
        let side: CGFloat = (percent > 0) ? 1 : 0
        
        for icon in page.subviews {
            let iconX = icon.frame.midX
            let iconY = icon.frame.midY
            let absX = iconX+side*(screenWidth-2*iconX)
            let pathX = page.width * side
            let pathY = page.height + 7 + icon.height/2
            let iconAngle = atan(iconY/absX)
            
            icon.translate((pathX-iconX)*fixed, (pathY-iconY)*fixed)
            icon.rotate(percent*iconAngle)
            icon.scale(sqrt(-fixed+1))
        }
    }

    private func verticalAntLines(_ page: UIView, _ offset: CGFloat) {
        let percent = offset/page.width
        
        page.translate(offset, 0)
        page.alpha = 1 - abs(percent)
        
        var direction: CGFloat = 1
        var lastX = page.width
        
        for icon in page.subviews {
            if lastX > icon.frame.origin.x {
                direction = -1
            }
            else {
                direction = -direction
            }
            
            lastX = icon.frame.origin.x
            
            icon.translate(0, direction*percent*page.height)
        }
    }

    private func verticalScrolling(_ page: UIView, _ offset: CGFloat) {
        let percent = offset/page.width
        page.translate(offset, percent*page.height)
        page.alpha = 1 - abs(percent)
    }
    
    private func vortex(_ page: UIView, _ offset: CGFloat) {
        let percent = abs(offset/page.width)
        
        let centerX = page.width/2
        let centerY = page.height/2 + 7
        var radius = 0.60 * centerX
        if radius > page.height {
            radius = 0.60 * page.height/2
        }
        
        let theta = (2 * .pi) / CGFloat(page.subviews.count)
        
        let stage1P = min(percent*3, 1)
        let stage2P = max(min((percent*3) - 1, 1), 0)
        
        let stage3P = stage2P*(.pi/3)
        let pi_6 = CGFloat.pi/6
        
        for (i, icon) in page.subviews.enumerated() {
            let iconAngle = theta*CGFloat(i) - pi_6 + stage3P
            
            let begX = icon.frame.midX
            let begY = icon.frame.midY
            
            let endX = centerX+radius*cos(iconAngle)
            let endY = centerY-radius*sin(iconAngle)
            
            icon.translate((endX-begX)*stage1P, (endY-begY)*stage1P)
            icon.rotate(-stage1P*(.pi / 2 + iconAngle))
        }
        
        page.alpha = 1 - stage2P
        page.translate(offset, 0)
    }
    
    private func wave(_ page: UIView, _ offset: CGFloat) {
        let percent = abs(offset/page.width)
        let numIcons = page.subviews.count
        
        for (i, icon) in page.subviews.enumerated() {
            let direction: CGFloat = (offset < 0) ? 1 : -1
            let iconIndex = CGFloat((offset < 0) ? numIcons - i: i - 1)
            
            let curIconPercent = percent - ((0.525 / CGFloat(numIcons)) * iconIndex)
            
            if curIconPercent > 0 {
                let dx = direction*(curIconPercent*pow(3.5, 2))*page.width
                icon.translate(dx, 0)
            }
        }
        
        page.translate(offset, 0)
    }

    private func wheel(_ page: UIView, _ offset: CGFloat) {
        page.layer.savePosition()
        page.layer.position.x += offset

        let percent = offset/page.width

        for icon in page.subviews {
            let iconCenterX = icon.frame.midX
            let iconCenterY = icon.frame.midY
            let iconCenterXOffset = page.width/2 - iconCenterX
            let iconRadius = screenHeight - iconCenterY

            let percent2 = ((offset < 0) ?  iconCenterX : page.width - iconCenterX) / page.width

            let angle = -percent*(1 + percent2*2) * CGFloat.pi/2

            icon.translate(iconCenterXOffset, iconRadius)
            icon.rotate(angle)
            icon.translate(-iconCenterXOffset, -iconRadius)
        }
    }
}
