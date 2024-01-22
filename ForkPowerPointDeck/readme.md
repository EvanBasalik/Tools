Given a PowerPoint document, it will iterate through all the slides in a PowerPoint deck and remove the unwanted ones.  It looks for the specified identifier in each slide's `Notes` field to determine which slides to keep.  This is great for keeping a single master deck while being able to create forks of that deck on demand for special sessions.

# Input parameters:
**-b{baseFile without .pptx}** = input deck  
**-o{outputFile without .pptx}** = name for output file  
**-i{identifier to keep}** = identifier to look in the Notes field to keep   
**-w** = if specified, allows overwriting of an existing output file by the same name  

On each slide, anywhere in the notes field, add an identifier.  In the sample, the identifiers are:

* {Scenario1}
* {Scenario2}
* {Scenario3}

When invoking with -i{Scenario1} - only slides that have {Scenario1} will be kept.