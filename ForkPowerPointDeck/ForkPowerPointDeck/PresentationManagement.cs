using DocumentFormat.OpenXml;
using DocumentFormat.OpenXml.Office2010.PowerPoint;
using DocumentFormat.OpenXml.Packaging;
using DocumentFormat.OpenXml.Presentation;

namespace ForkPowerPointDeck
{

    internal class SlideItem
    {
        public string IdentifyingText = string.Empty;
        public uint Id;
    };

    internal static class PresentationManagement
    {
        public static readonly string KeepAllSlidesIdentifier = "{KeepAllSlides}";

        internal static string GetNotesInSlide(PresentationDocument presentationDocument, int slideIndex)
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
            PresentationPart? presentationPart = presentationDocument.PresentationPart;

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
                        string? slidePartRelationshipId = (slideIds[slideIndex] as SlideId).RelationshipId;

                        if (slidePartRelationshipId != null)
                        {
                            // Get the specified slide part from the relationship ID.
                            SlidePart slidePart = (SlidePart)presentationPart.GetPartById(slidePartRelationshipId);

                            // Pass the slide part to the next method, and
                            // then return the array of strings that method
                            // returns to the previous method.
                            return GetNotesInSlide(slidePart);
                        }
                        else
                        {
                            return string.Empty;
                        }


                    }
                }
            }
            // Else, return empty string
            return string.Empty;
        }

        internal static string GetNotesInSlide(SlidePart slidePart)
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

        internal static bool RemoveCameoInSlide(PresentationDocument presentationDocument, int slideIndex)
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
            PresentationPart? presentationPart = presentationDocument.PresentationPart;

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
                        string? slidePartRelationshipId = (slideIds[slideIndex] as SlideId).RelationshipId;

                        if (slidePartRelationshipId != null)
                        {
                            // Get the specified slide part from the relationship ID.
                            SlidePart slidePart = (SlidePart)presentationPart.GetPartById(slidePartRelationshipId);

                            //loop through all the pictures in the slidePart
                            foreach (DocumentFormat.OpenXml.Presentation.Picture item in slidePart.Slide.Descendants<DocumentFormat.OpenXml.Presentation.Picture>())
                            {
                                //only remove if is a Cameo picture. We can tell because the name has "Camera" in it
                                if (item != null && item.NonVisualPictureProperties.NonVisualDrawingProperties.Name.ToString().Contains("Camera"))
                                {
                                    Console.WriteLine($"Found and removing a cameo with the name    {item.NonVisualPictureProperties.NonVisualDrawingProperties.Name} on slide {slidePart.Uri.ToString().Split("/").Last().Split(".")[0].ToLowerInvariant().Replace("slide", "")}");
                                    item.Remove();
                                }
                            }
                        }
                    }
                }
            }
            presentationDocument.Save();

            _result = true;

            return _result;
        }

        //leveraging the section deletion code from https://github.com/ShapeCrawler/ShapeCrawler/discussions/239
        internal static bool DeleteSections(PresentationDocument presentationDocument)
        {
            bool _result = false;

            try
            {

                var sectionList = presentationDocument.PresentationPart!.Presentation.PresentationExtensionList?.Descendants<SectionList>().First();

                if (sectionList == null)
                {
                    _result = true; // presentation doesn't have sections
                }

                List<Section> emptySectionList = new List<Section>();

                // Create list of empty sections
                foreach (Section section in sectionList)
                {
                    var isEmptySection = section.SectionSlideIdList.Count() == 0 ? true : false;

                    if (isEmptySection)
                    {
                        emptySectionList.Add(section);
                        Console.WriteLine($"Tagging section \"{section.Name}\" for removal");

                    }
                }

                // Remove empty sections
                foreach (var item in emptySectionList)
                {
                    sectionList.RemoveChild(item);
                    Console.WriteLine($"Removed section: {item.Name}");
                }

                _result = true;
            }
            catch (Exception)
            {

                throw;
            }

            return _result;
        }

        public static bool ForkPresentation(string baseFile, string outputFile, string identifierToKeep, bool overwriteOutput, bool removeCameos, bool removeComments, bool removeEmptySections)
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

                //make sure we have either a .ppt or .pptx extension. If neither, tack in a .pptx
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
                    //for the special case of KeepAllSlides, just jump out of the if and right to the cameo removal
                    if (_slidesWithIdentifierToKeep != KeepAllSlidesIdentifier)
                    {
                        if (slideNotes.ToLowerInvariant().Contains(_slidesWithIdentifierToKeep.ToLowerInvariant()) == false)
                        {
                            Console.WriteLine($"Marking slide {presentationPart.SlideParts.ElementAt<SlidePart>(slideIndex - 1).Uri.ToString().Split("/").Last().Split(".")[0].ToLowerInvariant().Replace("slide", "")} with slide index {sourceSlide.Id} for removal.");
                            SlideItem _slide = new SlideItem
                            {
                                Id = sourceSlide.Id,
                                IdentifyingText = slideNotes
                            };
                            slidestoDelete.Add(_slide);
                        }
                        else
                        {
                            Console.WriteLine($"Keeping slide {presentationPart.SlideParts.ElementAt<SlidePart>(slideIndex - 1).Uri.ToString().Split("/").Last().Split(".")[0].ToLowerInvariant().Replace("slide", "")} with slide index {sourceSlide.Id}.");
                        }
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

                //Remove all comments in the deck
                if (removeComments)
                {
                    DeleteComments(presentationDocument);
                }

                //find and remove any empty sections
                if (removeEmptySections)
                {
                    DeleteSections(presentationDocument);
                }

                //save the presentation to the doc
                presentation.Save();

                //save the doc
                presentationDocument.Save();

                presentationDocument.Dispose();


                _result = true;
            }
            catch (Exception)
            {

                throw;
            }

            return _result;
        }

        // Remove all the comments in the slides.
        internal static bool DeleteComments(PresentationDocument presentationDocument)
        {
            bool _result = false;

            try
            {
                // Verify that the presentation document exists.
                if (presentationDocument == null)
                {
                    throw new ArgumentNullException("presentationDocument");
                }

                // Get the presentation part of the presentation document.
                PresentationPart? presentationPart = presentationDocument.PresentationPart;

                // Verify that the presentation part and presentation exist.
                if (presentationPart != null && presentationPart.Presentation != null)
                {

                    IEnumerable<SlidePart>? slideParts = presentationPart?.SlideParts;

                    // If there's no slide parts, return.
                    if (slideParts is null)
                    {
                        return false;
                    }

                    // Iterate through all the slides and get the slide parts.
                    foreach (SlidePart slidePart in slideParts)
                    {

                        //iterate through all the parts
                        foreach (var part in slidePart.Parts)
                        {
                            //find the comment part
                            if (part.OpenXmlPart.ContentType == "application/vnd.ms-powerpoint.comments+xml")
                            {

                                // Get the OpenXmlPart object and conver to PowerPointCommentPart
                                PowerPointCommentPart slideCommentPart = (PowerPointCommentPart) part.OpenXmlPart;
                                {
                                    // Get the list of comments.
                                    if (slideCommentPart is not null)
                                    {
                                        //for some reason, have to use the Office2021 class
                                        foreach (DocumentFormat.OpenXml.Office2021.PowerPoint.Comment.Comment comm in slideCommentPart.CommentList)
                                        {
                                            // Delete each comment
                                            slideCommentPart.CommentList.RemoveChild(comm);
                                            Console.WriteLine($"Deleted a comment on slide {slidePart.Uri.ToString().Split("/").Last().Split(".")[0].ToLowerInvariant().Replace("slide", "")}");
                                        }

                                        // If the commentPart has no existing comments, then delete the slideCommentPart
                                        if (slideCommentPart.CommentList.ChildElements.Count == 0)
                                            // Delete this part.
                                            slidePart.DeletePart(slideCommentPart);
                                    }
                                }
                            }
                        }
                    }

                        _result = true;
                    }
            }
            catch (Exception ex)
            {

                throw ex;
            }


            return _result;
        }

    }
}
