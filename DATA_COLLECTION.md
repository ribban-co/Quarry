# Data Collection

Quarry can be built without any Quarry-hosted service configuration.

In a community build where `quarry/Secrets.xcconfig` is absent or leaves service values blank:

- PostHog analytics is not initialized;
- Sentry crash reporting is not initialized;
- WorkOS sign-in is unavailable; and
- Convex OAuth setup is unavailable (manual Convex connections remain available); and
- funded Bedrock AI access is unavailable.

Official builds may configure these services at build time. Analytics and crash-reporting controls are available in the app's settings. Build-time configuration is embedded in the distributed binary and is not a substitute for a server-side secret or authorization boundary.

Database content and credentials are sensitive. Do not include connection strings, query contents, database values, authentication responses, or user data in telemetry or bug reports.
