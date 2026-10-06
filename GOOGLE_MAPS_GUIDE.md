# TastyKart — Google Maps & API Key Guide

How the customer app uses **Google Maps**, where the **Maps API key** is configured, which Google APIs are called, and which screens depend on them.

---

## 1. Overview

| Item | Detail |
|------|--------|
| Package | `google_maps_flutter` |
| Supporting packages | `geolocator`, `geocoding`, `http` |
| **Google Maps API key** | `AIzaSyBwSjsnX7tDra6Wz5mw6wZRwRN57pi0NUM` |
| Key constant | `MapConstants.googleMapKey` in `lib/constants/map_constants.dart` |
| Default map center | Hyderabad — `LatLng(17.385044, 78.486671)` |
| Default zoom | `15` (picker) / `13.5` (tracking) |

The same API key is used for:

1. **Maps SDK** (native map tiles / `GoogleMap` widget) — Android & iOS
2. **Places API** (autocomplete + place details) — HTTP from Dart
3. **Geocoding API** (reverse geocode fallback) — HTTP from Dart

---

## 2. Where the map key is configured

**Current key (keep identical in all three places):**

```
AIzaSyBwSjsnX7tDra6Wz5mw6wZRwRN57pi0NUM
```

### A. Dart (Places + Geocoding HTTP)

**File:** `lib/constants/map_constants.dart`

```dart
class MapConstants {
  static const String googleMapKey = 'AIzaSyBwSjsnX7tDra6Wz5mw6wZRwRN57pi0NUM';
  static const LatLng defaultCenter = LatLng(17.385044, 78.486671);
  static const double defaultZoom = 15;
  static const double trackingZoom = 13.5;
}
```

### B. Android (Maps SDK)

**File:** `android/app/src/main/AndroidManifest.xml`

```xml
<meta-data
    android:name="com.google.android.geo.API_KEY"
    android:value="AIzaSyBwSjsnX7tDra6Wz5mw6wZRwRN57pi0NUM"/>
```

Also requires:

```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
```

### C. iOS (Maps SDK)

**File:** `ios/Runner/AppDelegate.swift`

```swift
import GoogleMaps

GMSServices.provideAPIKey("AIzaSyBwSjsnX7tDra6Wz5mw6wZRwRN57pi0NUM")
```

Location permission strings live in `ios/Runner/Info.plist` (`NSLocationWhenInUseUsageDescription`, etc.).

---

## 3. Google Cloud / Console setup

In [Google Cloud Console](https://console.cloud.google.com/) (project linked to this key), enable:

| API | Used for |
|-----|----------|
| **Maps SDK for Android** | `GoogleMap` on Android |
| **Maps SDK for iOS** | `GoogleMap` on iOS |
| **Places API** | Address search autocomplete + place details |
| **Geocoding API** | Reverse geocode fallback when platform geocoder fails |

### Recommended key restrictions

| Restriction | Guidance |
|-------------|----------|
| **Application** | Android: package `com.arrowcoders.foodapp` + SHA-1 (debug & release). iOS: bundle id `com.arrowcoders.foodapp`. |
| **API** | Restrict key to Maps SDK Android/iOS, Places API, Geocoding API only. |

> **Note:** HTTP calls from Dart (`PlacesService` / `GeocodingService`) use the key in the query string. If you restrict the key to Android/iOS apps only, those REST calls can fail (`REQUEST_DENIED`). Options:
>
> 1. Use a **second key** restricted by API (Places + Geocoding) for HTTP only, or  
> 2. Proxy Places/Geocoding through Cloud Functions and keep secrets off the client.

---

## 4. How the app uses maps

```
User picks / searches address
        │
        ├─► AddressSearchField ──► PlacesService.autocomplete (Places API)
        │                              │
        │                              └─► PlacesService.fetchDetails (lat/lng + address)
        │
        ├─► AddressMapPicker ──► GoogleMap (Maps SDK)
        │         │                    │
        │         │                    ├─ drag / tap pin
        │         │                    └─ “my location” (Geolocator)
        │         │
        │         └─► GeocodingService.reverseGeocode
        │                   │
        │                   ├─ platform geocoding package first
        │                   └─ Google Geocoding API fallback (same map key)
        │
        └─► Saved on customers/{uid}.addresses[] (lat, lng, fullAddress)

Order tracking
        └─► OrderTrackingMap ──► GoogleMap + markers (kitchen → delivery)
```

### Services

| Class | File | Role |
|-------|------|------|
| `PlacesService` | `lib/services/places_service.dart` | Places Autocomplete + Details using `MapConstants.googleMapKey` |
| `GeocodingService` | `lib/services/geocoding_service.dart` | Reverse geocode (platform → Google fallback); forward geocode via `geocoding` package |

### Widgets / screens

| Component | File | Role |
|-----------|------|------|
| `AddressMapPicker` | `lib/widgets/address_map_picker.dart` | Interactive pin map + optional search |
| `AddressSearchField` | `lib/widgets/address_search_field.dart` | Places autocomplete UI |
| `OrderTrackingMap` | `lib/widgets/order_tracking_map.dart` | Track order map (origin + destination markers) |
| `SelectLocationScreen` | `lib/screens/location/select_location_screen.dart` | Manage / pick delivery addresses |

---

## 5. Places API usage

**Autocomplete** — `GET https://maps.googleapis.com/maps/api/place/autocomplete/json`

Query params used in app:

- `input` — user text (min 2 chars)
- `key` — `MapConstants.googleMapKey`
- `components=country:in` — India only
- `location` — Hyderabad (`MapConstants.defaultCenter`)
- `radius=80000` — bias ~80 km
- `types=geocode|establishment`

**Details** — `GET https://maps.googleapis.com/maps/api/place/details/json`

- `place_id`, `fields=formatted_address,geometry,name`, `key`

Flow in UI: type → suggestions → tap → details → move map camera + fill address text.

---

## 6. Geocoding usage

**Reverse geocode** (`GeocodingService.reverseGeocode`):

1. Try device/platform `placemarkFromCoordinates` (`geocoding` package)
2. If empty/fails → Google Geocoding API:

`GET https://maps.googleapis.com/maps/api/geocode/json?latlng=lat,lng&key=...`

**Forward geocode** (`geocodeAddress`): uses platform `locationFromAddress` (e.g. order tracking when only an address string exists).

---

## 7. Device location (Geolocator)

`AddressMapPicker` uses `geolocator` for “current location”:

1. Check / request location permission  
2. Get current `Position`  
3. Animate camera + update pin  
4. Reverse-geocode to human-readable address  

Without permission, the map still works with default Hyderabad center or last known pin.

---

## 8. Map UI behaviour

### Address picker (`AddressMapPicker`)

- Initial camera: saved lat/lng, else `MapConstants.defaultCenter`
- User can search (Places), tap map, or drag marker
- On change → `onLocationChanged(LatLng)` + optional `onAddressResolved(String)`
- My-location button via Geolocator

### Order tracking (`OrderTrackingMap`)

- Destination from order lat/lng, or geocoded address, else default center
- “Kitchen” marker offset slightly from destination (visual route only — not live rider GPS)
- Zoom: `MapConstants.trackingZoom`

---

## 9. Rotating / updating the API key

When replacing the key, update **all three**:

1. `lib/constants/map_constants.dart` → `googleMapKey`
2. `android/app/src/main/AndroidManifest.xml` → `com.google.android.geo.API_KEY`
3. `ios/Runner/AppDelegate.swift` → `GMSServices.provideAPIKey(...)`

Then:

```bash
flutter clean
flutter pub get
# rebuild Android / iOS
```

Confirm APIs are enabled and restrictions allow your package + SHA-1 / bundle id.

---

## 10. Troubleshooting

| Symptom | Likely cause |
|---------|----------------|
| Blank / grey map on Android | Wrong/missing `com.google.android.geo.API_KEY`, Maps SDK for Android not enabled, or SHA-1 not allowed |
| Blank map on iOS | Missing `GMSServices.provideAPIKey`, Maps SDK for iOS not enabled |
| Autocomplete always empty | Places API not enabled, key restricted to apps only (blocks HTTP), billing disabled, or `REQUEST_DENIED` |
| Reverse address stays empty | Platform geocoder failed + Geocoding API denied / not enabled |
| My location fails | Location permission denied; check Manifest / Info.plist |
| Works in debug, fails in release | Release SHA-1 not added to Android key restriction in Cloud Console |

Check HTTP status in responses: Places/Geocoding return `status` fields like `OK`, `ZERO_RESULTS`, `REQUEST_DENIED`, `OVER_QUERY_LIMIT`.

---

## 11. Security notes

- The Maps key is **embedded in the client** (required for Maps SDK). Treat it as restrictable, not fully secret.
- Prefer **API + app restrictions** in Google Cloud.
- Do **not** commit unrestricted keys with billing unlimited.
- Razorpay / Firebase keys are unrelated — do not mix Maps key with payment secrets.
- For stronger security on Places/Geocoding, move REST calls to Cloud Functions and call them from Flutter.

---

## 12. Quick file index

| Path | Purpose |
|------|---------|
| `lib/constants/map_constants.dart` | Key + default camera |
| `lib/services/places_service.dart` | Places Autocomplete / Details |
| `lib/services/geocoding_service.dart` | Reverse / forward geocode |
| `lib/widgets/address_map_picker.dart` | Pin picker map |
| `lib/widgets/address_search_field.dart` | Search UI |
| `lib/widgets/order_tracking_map.dart` | Order track map |
| `android/app/src/main/AndroidManifest.xml` | Android Maps SDK key + location permissions |
| `ios/Runner/AppDelegate.swift` | iOS Maps SDK key |

---

*Keep this doc in sync when you change the map key, default city, or Places/Geocoding endpoints.*
