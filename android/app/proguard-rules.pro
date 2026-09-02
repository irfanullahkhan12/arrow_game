# R8 runs on release builds and renames classes. Two libraries here look their
# own classes up by name at runtime, so renaming them turns into a crash that
# only ever shows up in a release build.

# WorkManager, pulled in by home_widget for the widget's background callbacks.
# Room builds its database by appending "_Impl" to the class name and loading
# that by reflection; once R8 renames WorkDatabase the lookup fails and
# androidx.startup dies taking the whole process with it:
#   Unable to get provider androidx.startup.InitializationProvider:
#   Failed to create an instance of androidx.work.impl.WorkDatabase
-keep class androidx.work.** { *; }
-keep class * extends androidx.room.RoomDatabase { *; }
-keep class * extends androidx.work.Worker { *; }
-keep class * extends androidx.work.ListenableWorker { <init>(...); }
-dontwarn androidx.work.**

# Room itself, for the same reason.
-keep class androidx.room.** { *; }
-dontwarn androidx.room.paging.**

# androidx.startup discovers initializers by name from the merged manifest.
-keep class * implements androidx.startup.Initializer { *; }
