Given a PowerPoint document, it will iterate through all the slides in a PowerPoint deck and remove the unwanted ones.  It looks for the specified identifier in each slide's `Notes` field to determine which slides to keep.  This is great for keeping a single master deck while being able to create forks of that deck on demand for special sessions.

If you use the [Cameo feature](https://support.microsoft.com/en-us/office/presenting-with-cameo-83abdb2e-948a-47d0-932d-86815ae1317a) for an enhanced presentation, you can also use ForkPowerPointDeck to remove Cameos on all the slides.

There is an EXE for commandline or scripting use and a WinForms UI.

![image](https://github.com/EvanBasalik/Tools/assets/4534993/edfc0f62-8943-44e2-9a45-b615ce684a64)


# Input parameters:
**-b{baseFile without .pptx}** = input deck  
**-o{outputFile without .pptx}** = name for output file  
**-i{identifier to keep}** = identifier to look in the Notes field to keep   
**-w** = if specified, allows overwriting of an existing output file by the same name  
**-c** = if specified, removes Cameos from all slides

On each slide, anywhere in the notes field, add an identifier.  In the sample PowerPoint file (SampleInput.pptx), the identifiers are:

* {Scenario1}
* {Scenario2}
* {Scenario3}

When invoking with -i{Scenario1} - only slides that have {Scenario1} will be kept.
