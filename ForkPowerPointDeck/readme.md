Given a mapping file of which slides to remove and which to keep, will iterate through all the slides in a PowerPoint deck and remove the unwanted ones. This is great for keeping a single master deck while being able to create forks of that deck on demand for special sessions.

# Input parameters:
-b{baseFile without .pptx} = input deck
-o{outputFile without .pptx} = name for output file
-m{mappingFileCSV without .csv} = mapping file that lists all the slides by number (1.._n_) and whether to "keep" or "remove" them
-w = if specified, allows overwriting of an existing output file by the same name