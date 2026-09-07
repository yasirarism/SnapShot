module.exports = {
  apps: [
    {
      name: "snapshot-api",
      cwd: "/var/www/snapshot/artifacts/api-server",
      script: "dist/index.mjs",
      interpreter: "node",
      env: {
        NODE_ENV: "production",
        PORT: "4000",
        DATABASE_URL: "postgres://snapshot_user:Silentwolf906.@localhost:5432/snapshot"
      }
    }
  ]
};
