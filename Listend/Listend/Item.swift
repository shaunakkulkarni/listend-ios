//
//  Item.swift
//  Listend
//
//  Created by Shaunak Kulkarni on 4/23/26.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
