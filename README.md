# v_monitor

Cross-platform monitoring app for enterprise device attendance and movement
management. The current UAV scope monitors the UAV controller/handheld, not the
aircraft itself.

## Flutter

```powershell
flutter pub get
flutter run -d windows
```

## Database

The initial PostgreSQL/PostGIS schema is in:

```text
backend/migrations/0001_uav_controller_monitoring.sql
```

For now, apply it manually to your local PostgreSQL database when needed.
