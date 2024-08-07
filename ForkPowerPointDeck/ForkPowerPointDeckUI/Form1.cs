using DocumentFormat.OpenXml.Presentation;
using ForkPowerPointDeck;
using System.Text.RegularExpressions;
using System.Windows.Forms;

namespace ForkPowerPointDeckUI
{
    public partial class Form1 : Form
    {
        string strBaseFile = string.Empty;
        string strOutputFile = string.Empty;
        string strOutputFolder = string.Empty;
        string strIdentifier = string.Empty;
        bool overwriteOutputFile = false;
        string strOutputFileandFolder = string.Empty;
        bool removeCameos = false;

        public Form1()
        {
            InitializeComponent();

            //redirect all the console.writelines in the class and form to txtProgress
            Console.SetOut(new ControlWriter(txtProgress));
        }

        private void Form1_Load(object sender, EventArgs e)
        {
            //load the list of stored identifiers and bind to lstIdentifiers
            
            //if not already present from a previous run, add the special case scenario of {KeepAll}
            //this will allow us to clean up cameos and empty sections without deleting any slides
            if (Properties.Settings.Default.Identifiers.IndexOf(PresentationManagement.KeepAllSlidesIdentifier) == -1)
            {
                Properties.Settings.Default.Identifiers.Add(PresentationManagement.KeepAllSlidesIdentifier);
            }

            lstIdentifiers.DataSource = Properties.Settings.Default.Identifiers;
        }

        private void btnAdd_Click(object sender, EventArgs e)
        {
            //ensure the new identifier has {}
            string pattern = @"\{.*?\}";
            if (Regex.IsMatch(txtNewIdentifier.Text, pattern))
            {
                //if it does, add it to the persistent list
                Properties.Settings.Default.Identifiers.Add(txtNewIdentifier.Text);
                Properties.Settings.Default.Save();

                //bounce the datasource to force a refresh in the UI
                lstIdentifiers.DataSource = null;
                lstIdentifiers.DataSource = Properties.Settings.Default.Identifiers;
            }
            else
            {
                MessageBox.Show("The text identifier must start with '{' and end with '}'", "Identifier format error", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        private void btnDelete_Click(object sender, EventArgs e)
        {
            if (lstIdentifiers.SelectedIndex >= 0)
            {
                //only allow the removal if not the special indentifier KeepAllSlides
                if (lstIdentifiers.SelectedItem.ToString() != PresentationManagement.KeepAllSlidesIdentifier)
                {
                    Properties.Settings.Default.Identifiers.Remove(lstIdentifiers.SelectedItem.ToString());
                }
                else
                {
                    MessageBox.Show($"Cannot delete special identifier {PresentationManagement.KeepAllSlidesIdentifier}", "Special identifier", MessageBoxButtons.OK, MessageBoxIcon.Stop);
                }

                //bounce the datasource to force a refresh in the UI
                lstIdentifiers.DataSource = null;
                lstIdentifiers.DataSource = Properties.Settings.Default.Identifiers;
            }

        }

        private void btnBaseFile_Click(object sender, EventArgs e)
        {
            //filter to just show PowerPoint files
            openFileDialog.Filter = "PowerPoint Files|*.ppt;*.pptx";
            openFileDialog.InitialDirectory = Environment.CurrentDirectory;
            openFileDialog.ShowDialog(this);

            //grab the selected file and store it as the base file
            strBaseFile = openFileDialog.FileName.ToString();
            txtBaseFile.Text = strBaseFile;
        }

        private void btnOutputFolder_Click(object sender, EventArgs e)
        {
            //browse for a folder
            using (var dialog = new FolderBrowserDialog())
            {
                dialog.InitialDirectory = Environment.CurrentDirectory;
                DialogResult result = dialog.ShowDialog();
                if (result == DialogResult.OK && !string.IsNullOrWhiteSpace(dialog.SelectedPath))
                {
                    txtOutputFolder.Text = dialog.SelectedPath;
                    strOutputFolder = dialog.SelectedPath;
                }
            }
        }

        private void txtBaseFile_TextChanged(object sender, EventArgs e)
        {
            strBaseFile = txtBaseFile.Text;
        }

        private void txtOutputFolder_TextChanged(object sender, EventArgs e)
        {
            strOutputFile = txtOutputFolder.Text;
        }

        private void txtOutputFile_TextChanged(object sender, EventArgs e)
        {
            strOutputFile = txtOutputFile.Text;
        }

        private void chkOverwrite_CheckedChanged(object sender, EventArgs e)
        {
            overwriteOutputFile = chkOverwrite.Checked;
        }

        private void btnFork_Click(object sender, EventArgs e)
        {
            try
            {
                //clear the progress box
                txtProgress.Clear();

                //merge the output folder and file
                strOutputFileandFolder = Path.Combine(strOutputFolder, strOutputFile);

                //get the currently selected identifier
                strIdentifier = lstIdentifiers.SelectedItem.ToString();

                if (strBaseFile != string.Empty && strOutputFile != string.Empty
                        && strIdentifier != string.Empty && strOutputFolder != string.Empty)
                {
                    PresentationManagement.ForkPresentation(strBaseFile, strOutputFileandFolder, strIdentifier, overwriteOutputFile, removeCameos, chkRemoveComments.Checked, chkRemoveEmptySections.Checked);

                    //force the progress report to scroll to the bottom
                    txtProgress.ScrollToCaret();
                }
                else
                {
                    //figure out which one is missing and show in a dialog
                    string missingInput = string.Empty;
                    if (strBaseFile == string.Empty)
                    {
                        missingInput = "base file";
                    }
                    if (strOutputFolder == string.Empty)
                    {
                        missingInput = "output folder";
                    }
                    if (strOutputFile == string.Empty)
                    {
                        missingInput = "output file";
                    }
                    if (strIdentifier == string.Empty)
                    {
                        missingInput = "identifier";
                    }
                    MessageBox.Show($"You haven't specified the {missingInput}", "Missing input", MessageBoxButtons.OK, MessageBoxIcon.Error);
                }

            }
            catch (Exception ex)
            {
                MessageBox.Show("Unable to fork deck!", "Fork Error!", MessageBoxButtons.OK, MessageBoxIcon.Error);
                Console.WriteLine(ex.Message);
            }
        }

        private void Form1_FormClosing(object sender, FormClosingEventArgs e)
        {
            Properties.Settings.Default.Save();
        }

        private void chkRemoveCameos_CheckedChanged(object sender, EventArgs e)
        {
            removeCameos = chkRemoveCameos.Checked;
        }
    }
}
