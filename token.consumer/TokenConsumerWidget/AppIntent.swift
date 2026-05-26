//
//  AppIntent.swift
//  TokenConsumerWidget
//
//  Created by Vitor Furini on 25/05/26.
//

import WidgetKit
import AppIntents

struct ConfigurationAppIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Token Usage" }
    static var description: IntentDescription { "Shows your OpenAI organization usage from the app settings or this widget configuration." }

    @Parameter(title: "OpenAI Admin Key", default: "")
    var adminKey: String
}
