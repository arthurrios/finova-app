# Project-specific R8 rules.

# Credential Manager finds its Play services provider by reflection (Google sign-in). Without this,
# R8 removes it and release builds fail to show the account picker.
-if class androidx.credentials.CredentialManager
-keep class androidx.credentials.playservices.** {
  *;
}
