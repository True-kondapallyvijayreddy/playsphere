# 26. Gallery & Media Management

## 1. Overview
The Gallery & Media system serves as the visual memory for organizations and players. It allows for the upload, auto-tagging, and viewing of photos and videos linked to specific matches, seasons, and player profiles. 

## 2. Core Features
- **Cloud Storage**: Media assets are securely stored via AWS S3 or Firebase Cloud Storage, utilizing CDNs for fast, global delivery.
- **Event Albums**: Automatic creation of albums per Season and per Fixture.
- **Auto-Tagging (Metadata)**: Uploaded media is tagged with contextual metadata (Event ID, Sport, Season).
- **Player Tagging**: Admins and users can tag specific players in media, adding the media to the player's Portable Career Resume.
- **Community Contributions**: Approved participants can upload their own media to a shared community pool, subject to admin moderation.

## 3. Media Upload Workflow
1. User selects media in Flutter app (using `image_picker`).
2. App requests a presigned upload URL from the backend.
3. App uploads binary directly to S3/Firebase (bypassing backend bandwidth).
4. On success, app notifies backend, creating a `MediaAssetEntity`.
5. Background job generates thumbnails (for images) or compressed previews (for videos).

## 4. Moderation & Safety
- **Report System**: Any user can flag inappropriate content.
- **Moderation Queue**: Flagged content is hidden and moved to the Org Admin's review queue.
- **Minor Privacy**: If a minor is tagged, guardians receive a notification and can opt to untag or request deletion of the media.

## 5. Data Model
- **MediaAssetEntity**:
  - `id`: String (UUID)
  - `orgId`: String
  - `uploaderId`: String
  - `url`: String (Original)
  - `thumbnailUrl`: String
  - `type`: Enum (IMAGE, VIDEO)
  - `linkedEventId`: String (Optional)
  - `taggedUserIds`: List<String>
  - `status`: Enum (ACTIVE, PENDING_MODERATION, DELETED)
  - `createdAt`: Timestamp

## 6. UI/UX Considerations
- Masonry grid layout for gallery views.
- Pinch-to-zoom for images.
- Inline auto-playing, muted video previews (similar to Instagram).
