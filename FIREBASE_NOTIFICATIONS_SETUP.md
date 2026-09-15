# MAINTAIN AI Workforce — Push Notifications Setup

The Workforce Client now contains Firebase Cloud Messaging support. The existing MAINTAIN AI backend and Neon database remain the source of truth; Firebase is only used for push delivery.

## 1. Create the Firebase Android app

Create or use the Firebase project for MAINTAIN AI and add an Android application whose package ID matches the generated Flutter Android package.

Download `google-services.json` and keep it outside Git until the project is configured for the production build pipeline.

## 2. Configure the Android build

The repository intentionally does not contain a Firebase project credential or `google-services.json`.

The CI workflow regenerates the Android project with `flutter create`, so Firebase Android configuration needs to be injected into that workflow before `flutter build apk`.

Recommended GitHub Actions secret:

`FIREBASE_ANDROID_CONFIG_BASE64`

Store the base64-encoded contents of `google-services.json` as that secret and create `android/app/google-services.json` during the Android build job.

The Google Services Gradle plugin must also be enabled in the generated Android project.

## 3. Configure the backend

Add the Firebase Admin service-account JSON to the deployed MAINTAIN AI backend as a server environment variable:

`FIREBASE_SERVICE_ACCOUNT_JSON`

Never commit the service-account JSON, private key, or any Firebase Admin credential to Git.

## 4. Notification flow

```text
Engineer creates/assigns work order
             ↓
        Neon PostgreSQL
             ↓
    MAINTAIN AI notification service
             ↓
 Firebase Cloud Messaging (FCM)
             ↓
       Worker Android phone
```

The same flow is used for faults and critical machine alerts.

## 5. Events

The backend creates a persistent in-app notification and attempts an FCM push for:

- Every newly assigned work order
- Every reported fault
- High/critical machine alerts
- Critical machine health conditions
- Reassignment of an existing work order

If Firebase is temporarily unavailable, the notification remains persisted in Neon so it is still visible in the in-app notification center.
