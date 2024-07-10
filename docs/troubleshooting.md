# Syphon's Known Questions

### GC Warning: Could not open /proc/stat

This occurs because the Garbage Collector doesn't have the permission to know what cpu cores are available and then uses 1 core as a default, to solve this just set GC_NPROCS environment variable as the amount of cpu cores you have
