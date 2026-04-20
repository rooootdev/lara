//
//  helpers.swift
//  lara
//
//  Created by ruter on 20.04.26.
//

func hex(_ value: UInt64) -> String {
    "0x" + String(value, radix: 16, uppercase: true)
}
