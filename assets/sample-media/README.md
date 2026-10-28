# COMPARTS sample media

Original vector illustrations for the sample catalog, account avatars and shop
logo. Product artwork is a generic category illustration, not a manufacturer
photograph of the exact listed product. Product records preserve that label.

The SVG sources, PNG exports and SHA-256 manifest are kept here for reproducible
uploads. They are not registered as Flutter assets or bundled into the APK.
The configured app loads public Supabase Storage URLs stored in database/Auth
records. Code-drawn placeholders remain available during loading or errors.

Render the media with the isolated build-time tool:

```powershell
npm.cmd install --prefix build/sample-media-tools --no-save --package-lock=false @resvg/resvg-js@2.6.2
node scripts/render-sample-media.mjs
```

After applying migration `202610280008_sample_media.sql`, upload or audit:

```powershell
node scripts/sample-media.mjs audit
node scripts/sample-media.mjs upload
node scripts/sample-media.mjs verify
```

The dedicated public bucket is `comparts-sample-media`. Object names contain a
content hash to prevent stale image caches after artwork changes. Sample media
can be read publicly; anonymous/authenticated clients cannot upload, replace,
or delete it. Backend service credentials are required for those operations.
