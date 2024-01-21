using Microsoft.VisualBasic.FileIO;
using System;
using System.Collections;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace ForkPowerPointDeck
{
    internal class SlideMapping
    {
        private List<MappingItem> _items;
        public List<MappingItem> MappingItems
        {
            get
            {

                if (_items == null)
                {
                    _items = new List<MappingItem>();
                }

                return _items;
            }
        }

        private string _mappingFile="";
        public string MappingFile
        {

            get 
            {
                return _mappingFile;
            }

            set
            {
                _mappingFile = value;

                //if the mapping file name is set, clear out the existing collection
                _items = new List<MappingItem>();

                //if the mapping file location is defined and the collection is null
                //read in the file and build the mapping
                if (MappingFile != "")
                {
                    //read in the files
                    using (TextFieldParser parser = new TextFieldParser(MappingFile))
                    {
                        parser.TextFieldType = FieldType.Delimited;
                        parser.SetDelimiters(",");
                        while (!parser.EndOfData)
                        {
                            string[] fields = parser.ReadFields();


                            MappingItem _slide = new MappingItem();

                            //first column is the slide index
                            try
                            {
                                _slide.SlideIndex = int.Parse(fields[0]);
                            }
                            catch (FormatException)
                            {
                                string message = $"The first column could not be parsed into a slide number for row {parser.LineNumber - 1}. The value in the column was \"{fields[0]}\"";
                                Console.WriteLine(message);
                                throw new Exception(message);
                            }

                            //second column is the keep/remove
                            //first column is the slide index

                            switch (fields[1].ToLowerInvariant())
                            {
                                case "keep":
                                    Console.WriteLine($"Tagging slide {_slide.SlideIndex} for keeping");
                                    _slide.KeepSlide = true;
                                    break;
                                case "remove":
                                    Console.WriteLine($"Tagging slide {_slide.SlideIndex} for removal");
                                    _slide.KeepSlide = false;
                                    break;
                                default:
                                    string message = $"The second column could not be parsed into keep/remove for row {parser.LineNumber - 1}. The value in the column was \"{fields[1]}\"";
                                    Console.WriteLine(message);
                                    throw new Exception(message);
                            }

                            //since the slide definition is good, add to our collection
                            _items.Add(_slide);
                        }
                    }

                }
            }
        }
        
    }

    internal class MappingItem
    {
        public int SlideIndex { get; set; }
        public bool KeepSlide { get; set; }
    }
}
