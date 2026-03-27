# Canvas Course Copy + Schedule Shift

This script automates Canvas course rollover for a new semester:

1. Copies content from last year's course into this semester's course.
2. Shifts assignment due/unlock/lock dates by the start-date offset.
3. Shifts module unlock dates by the same offset.

This is useful when you want this semester to follow the same cadence as last year.

## Prerequisites

- A Canvas API token with permission to read/update both courses.
- Course IDs for the source (last year) and destination (this semester) courses.
- PowerShell 7+ recommended.

## Usage

Set your token (or pass `-CanvasApiToken`):

```powershell
$env:CANVAS_API_TOKEN = "<your-token>"
```

Run the rollover:

```powershell
./CanvasCourseSchedule.ps1 \
  -CanvasBaseUrl "https://<your-school>.instructure.com" \
  -SourceCourseId 12345 \
  -DestinationCourseId 67890 \
  -SourceCourseStartDate "2025-01-08" \
  -DestinationCourseStartDate "2026-01-13"
```

If you already copied content manually and only need date shifting, use:

```powershell
./CanvasCourseSchedule.ps1 \
  -CanvasBaseUrl "https://<your-school>.instructure.com" \
  -SourceCourseId 12345 \
  -DestinationCourseId 67890 \
  -SourceCourseStartDate "2025-01-08" \
  -DestinationCourseStartDate "2026-01-13" \
  -SkipCourseCopy
```

## Notes

- The script updates dates in the destination course only.
- Run once per destination course rollover to avoid shifting dates multiple times.
- API rate limits depend on your Canvas tenant.
