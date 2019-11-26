//
//  SensorStuct.swift
//  SparkPerso
//
//  Created by  on 15/11/2019.
//  Copyright © 2019 AlbanPerli. All rights reserved.
//

import Foundation


struct SensorStuct: Codable {
    let type: String
    let value: [[Double]]

    private enum CodingKeys: String, CodingKey {
        case type = "type"
        case value = "value"
    }
}
