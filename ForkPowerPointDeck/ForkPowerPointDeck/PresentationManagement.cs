﻿using DocumentFormat.OpenXml.Packaging;
using DocumentFormat.OpenXml.Presentation;
using DocumentFormat.OpenXml.Presentation;
using DocumentFormat.OpenXml.Drawing;
using Shape = DocumentFormat.OpenXml.Presentation.Shape;
using DocumentFormat.OpenXml.Office.Drawing;

namespace ForkPowerPointDeck
{
    internal class SlideItem
    {
        public string IdentifyingText = string.Empty;
        public uint Id;
    };

    internal static class PresentationManagement
    {
        public static string GetNotesInSlide(PresentationDocument presentationDocument, int slideIndex)
        {
            // Verify that the presentation document exists.
            if (presentationDocument == null)
            {
                throw new ArgumentNullException("presentationDocument");
            }

            // Verify that the slide index is not out of range.
            if (slideIndex < 0)
            {
                throw new ArgumentOutOfRangeException("slideIndex");
            }

            // Get the presentation part of the presentation document.
            PresentationPart presentationPart = presentationDocument.PresentationPart;

            // Verify that the presentation part and presentation exist.
            if (presentationPart != null && presentationPart.Presentation != null)
            {
                // Get the Presentation object from the presentation part.
                Presentation presentation = presentationPart.Presentation;

                // Verify that the slide ID list exists.
                if (presentation.SlideIdList != null)
                {
                    // Get the collection of slide IDs from the slide ID list.
                    var slideIds = presentation.SlideIdList.ChildElements;

                    // If the slide ID is in range...
                    if (slideIndex < slideIds.Count)
                    {
                        // Get the relationship ID of the slide.
                        string slidePartRelationshipId = (slideIds[slideIndex] as SlideId).RelationshipId;

                        // Get the specified slide part from the relationship ID.
                        SlidePart slidePart = (SlidePart)presentationPart.GetPartById(slidePartRelationshipId);

                        // Pass the slide part to the next method, and
                        // then return the array of strings that method
                        // returns to the previous method.
                        return GetNotesInSlide(slidePart);
                    }
                }
            }
            // Else, return empty string
            return string.Empty;
        }

        public static string GetNotesInSlide(SlidePart slidePart)
        {
            // Verify that the slide part exists.
            if (slidePart == null)
            {
                throw new ArgumentNullException("slidePart");
            }

            // If the notes exist ...
            var notes = slidePart?.NotesSlidePart?.NotesSlide?.InnerText;

            if (string.IsNullOrWhiteSpace(notes) == false)
            {
                return notes;
            }
            else
            {
                return string.Empty;
            }
        }

        public static bool RemoveCameoInSlide(PresentationDocument presentationDocument, int slideIndex)
        {
            bool _result = false;

            // Verify that the presentation document exists.
            if (presentationDocument == null)
            {
                throw new ArgumentNullException("presentationDocument");
            }

            // Verify that the slide index is not out of range.
            if (slideIndex < 0)
            {
                throw new ArgumentOutOfRangeException("slideIndex");
            }

            // Get the presentation part of the presentation document.
            PresentationPart presentationPart = presentationDocument.PresentationPart;

            // Verify that the presentation part and presentation exist.
            if (presentationPart != null && presentationPart.Presentation != null)
            {
                // Get the Presentation object from the presentation part.
                Presentation presentation = presentationPart.Presentation;

                // Verify that the slide ID list exists.
                if (presentation.SlideIdList != null)
                {
                    // Get the collection of slide IDs from the slide ID list.
                    var slideIds = presentation.SlideIdList.ChildElements;

                    // If the slide ID is in range...
                    if (slideIndex < slideIds.Count)
                    {
                        // Get the relationship ID of the slide.
                        string slidePartRelationshipId = (slideIds[slideIndex] as SlideId).RelationshipId;

                        // Get the specified slide part from the relationship ID.
                        SlidePart slidePart = (SlidePart)presentationPart.GetPartById(slidePartRelationshipId);

                        //loop through all the pictures in the slidePart
                        foreach (DocumentFormat.OpenXml.Presentation.Picture item in slidePart.Slide.Descendants<DocumentFormat.OpenXml.Presentation.Picture>())
                        {
                            Console.WriteLine($"Found and removing a cameo with the name {item.NonVisualPictureProperties.NonVisualDrawingProperties.Name} on slide {slideIndex}");
                            item.Remove();
                        }
                    }
                }
            }
            presentationDocument.Save();
            
            _result = true;

            return _result;
        }

        public static bool ForkPresentation(string baseFile, string outputFile, string identifierToKeep, bool overwriteOutput, bool removeCameos)
        {

            bool _result = false;

            try
            {

                //to minimize code change from prior to moving this to a class
                //map the locals to the parameters
                //that way, we don't have to fix all the locals in this function
                string _baseFile = baseFile;
                string _outputFile = outputFile;
                string _slidesWithIdentifierToKeep = identifierToKeep;
                bool _overwriteOutput = overwriteOutput;

                //make sure we have a .pptx extension
                if (!(_outputFile.Contains(".pptx") | _outputFile.Contains(".ppt")))
                {
                    _outputFile = _outputFile + ".pptx";
                }

#if DEBUG
                //tack a date/time on the end just to make iteratively testing easier
                _outputFile = _outputFile.Replace(".pptx", DateTime.Now.ToString("yyyyMMddHHmmss") + ".pptx");

                Console.WriteLine("outputFile = " + _outputFile);
#endif

                //since we are overwriting any existing output file with the same name
                //exit if the target output file already exists and w(overWrite) isn't set
                if (!_overwriteOutput && File.Exists(_outputFile))
                {
                    Console.WriteLine("Output file already exists!");
                    return false;
                }

                //make a copy of the base file
                File.Copy(_baseFile, _outputFile, true);

                //open up the doc
                PresentationDocument presentationDocument = PresentationDocument.Open(_outputFile, true);

                //get the presentation part from the presentation document.
                PresentationPart? presentationPart = presentationDocument.PresentationPart;
                Presentation? presentation = presentationPart?.Presentation;

                //get the slide list
                SlideIdList? slideIdList = presentation.SlideIdList;

                //make sure we actually have slides
                if (slideIdList is null)
                {
                    throw new ArgumentNullException(nameof(slideIdList));
                }

                //unfortunately, no easy way ahead of time to know the slideId
                //therefore, we'll just track which slides to keep/remove by mapping against the order in the deck
                //this means we have to take a pass through and for each slide in order, compare the index against the mapping,
                //then if it needs to be deleted, grab the SlideId and store it so we can loop through again later to delete
                List<SlideItem> slidestoDelete = new List<SlideItem>();
                for (int slideIndex = 1; slideIndex < presentationPart.SlideParts.Count() + 1; slideIndex++)
                {
                    // Get the slide
                    SlideId? sourceSlide = slideIdList.ChildElements[slideIndex - 1] as SlideId;

                    string slideNotes = PresentationManagement.GetNotesInSlide(presentationDocument, slideIndex - 1);

                    //decide to keep or delete slide based on the input mapping file
                    //if the slide needs removed, grab the SlideId and add it to the slidestoDelete arrary
                    if (slideNotes.ToLowerInvariant().Contains(_slidesWithIdentifierToKeep.ToLowerInvariant()) == false)
                    {
                        Console.WriteLine($"Marking slide {slideIndex} with slide index {sourceSlide.Id} for removal.");
                        SlideItem _slide = new SlideItem
                        {
                            Id = sourceSlide.Id,
                            IdentifyingText = slideNotes
                        };
                        slidestoDelete.Add(_slide);
                    }
                    else
                    {
                        Console.WriteLine($"Keeping slide {slideIndex} with slide index {sourceSlide.Id}.");
                    }

                    //if removeCameos = true, remove cameo from the slide
                    if (removeCameos)
                    {
                        RemoveCameoInSlide(presentationDocument, slideIndex - 1);
                    }

                }

                //now that we have our list of slidestoDelete,
                //iterate through the slide list and find them one by one
                //when we find one, delete it, then restart the loop
                //we have to restart the loop because the index has changed
                foreach (var item in slidestoDelete)
                {
                    foreach (SlideId slide in slideIdList.Elements<SlideId>())
                    {
                        if (slide.Id == item.Id)
                        {
                            Console.WriteLine($"Removing slide {slide.Id}.");
                            slide.Remove();
                            break;
                        }
                    }
                }

                //save the presentation to the doc
                presentation.Save();

                //save the doc
                presentationDocument.Save();

                _result = true;
            }
            catch (Exception)
            {

                throw;
            }

            return _result;
        }

    }
}
