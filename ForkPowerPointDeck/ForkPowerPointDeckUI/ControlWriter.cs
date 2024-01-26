using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace ForkPowerPointDeckUI
{
    using System.IO;
    using System.Windows.Forms;

    public class ControlWriter : TextWriter
    {
        private readonly Control textbox;

        public ControlWriter(Control textbox)
        {
            this.textbox = textbox;
        }

        public override void Write(char value)
        {
            textbox.Text += value;
        }

        public override void Write(string value)
        {
            textbox.Text += value;
        }

        public override Encoding Encoding => Encoding.ASCII;
    }
}
