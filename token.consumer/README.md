# AI Token Consumer Widget

macOS widget for tracking OpenAI USD spend and token usage for the current month.

The app saves the OpenAI Admin Key in the macOS Keychain. No API key should be committed to the repository.

## Requirements

- macOS with WidgetKit support.
- Xcode installed.
- An OpenAI Admin Key with read permission for organization usage/costs.
- An Apple Developer account configured in Xcode to sign the app and widget.

## Running locally

1. Clone the repository:

   ```sh
   git clone <repository-url>
   cd ai-token-consumer-widget
   ```

2. Open the project in Xcode:

   ```sh
   open token.consumer/token.consumer.xcodeproj
   ```

3. In `Signing & Capabilities`, select your Team for both targets:

   - `token.consumer`
   - `TokenConsumerWidgetExtension`

4. Replace the sample identifiers with your own unique identifiers:

   - `PRODUCT_BUNDLE_IDENTIFIER`: this project uses `com.vitorfurini.token-consumer`.
   - `APP_GROUP_IDENTIFIER`: this project uses `group.vitorfurini.token-consumer`.

   Configure the same `APP_GROUP_IDENTIFIER` in both targets. The app and widget use this App Group to share preferences and the Keychain reference.

5. Confirm that both targets have the following capabilities:

   - App Groups, using the same App Group.
   - Keychain Sharing, using the same access group.
   - Outgoing Connections/Network Client, to call the OpenAI API.

6. Run the `token.consumer` target.

7. In the app, enter the `OpenAI Admin Key` and click `Save key`.

8. Optionally enter:

   - Project ID.
   - Monthly token reference.
   - Monthly budget in USD.

9. Add the `AI Token Usage` widget to the macOS Notification Center.

The widget requests an update every 5 minutes. macOS may delay or batch updates to save energy, so this is not guaranteed real-time behavior.

## Installing on Mac

To use the app outside Xcode:

1. In Xcode, select the `token.consumer` scheme.
2. Use `Product > Archive`.
3. In the Organizer window, export the app for local distribution or Developer ID, depending on your Apple account.
4. Copy the exported app to `/Applications`.
5. Open the app once, save the Admin Key, and then add the widget in macOS.

If macOS blocks the app because of signing/notarization, check the export options in Xcode and the permissions in `System Settings > Privacy & Security`.

## Data Used

The project calls these endpoints directly:

- `GET https://api.openai.com/v1/organization/usage/completions`
- `GET https://api.openai.com/v1/organization/costs`

The request uses `start_time` at the start of the current month, `bucket_width=1d`, and `limit=31`.

## Security

- Do not put your OpenAI Admin Key in project files, README, issues, or commits.
- The key entered in the app is stored in the Keychain shared between the app and widget.
- Non-sensitive preferences are stored in `UserDefaults(suiteName:)` inside the App Group.
- If a real key was accidentally committed, revoke that key in the OpenAI dashboard and generate another one. Removing it from code does not invalidate a key that has already become public.

## Notes

- The key needs organization-level administrative permission to query usage/costs.
- Cost values come from the Costs API. If that call fails, the widget still tries to show tokens.
- The widget's primary metric is USD spend returned by the Costs API.
- The local alert is sent once per month when spend passes 50% of the configured monthly budget. If there is no budget/cost, it uses tokens as a fallback.
- A macOS app does not send local notifications directly to Apple Watch. That requires an iOS/watchOS app, push via APNs, or an intermediary service with a Watch app.

How the widget should be appear

Small size:
<img width="202" height="190" alt="image" src="https://github.com/user-attachments/assets/dada9951-7afc-452a-ac6a-c49c586b8c52" />

Medium size:
<img width="370" height="182" alt="image" src="https://github.com/user-attachments/assets/29293da6-bf77-4a7a-81af-1299a14951be" />

