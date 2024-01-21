using System;
using System.Collections;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace ForkPowerPointDeck
{
    internal class Mapping
    {
        public IEnumerable<MappingItem> MappingItems { get; set; }
        public string MappingFile { get; set; }
    }

    internal class MappingItem
    {
        public int SlideIndex { get; set; }
        public bool KeepSlide { get; set; }
    }
}
