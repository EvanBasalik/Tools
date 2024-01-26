namespace ForkPowerPointDeckUI
{
    partial class Form1
    {
        /// <summary>
        ///  Required designer variable.
        /// </summary>
        private System.ComponentModel.IContainer components = null;

        /// <summary>
        ///  Clean up any resources being used.
        /// </summary>
        /// <param name="disposing">true if managed resources should be disposed; otherwise, false.</param>
        protected override void Dispose(bool disposing)
        {
            if (disposing && (components != null))
            {
                components.Dispose();
            }
            base.Dispose(disposing);
        }

        #region Windows Form Designer generated code

        /// <summary>
        ///  Required method for Designer support - do not modify
        ///  the contents of this method with the code editor.
        /// </summary>
        private void InitializeComponent()
        {
            chkOverwrite = new CheckBox();
            txtBaseFile = new TextBox();
            lstIdentifiers = new ListBox();
            openFileDialog1 = new OpenFileDialog();
            txtOutputFolder = new TextBox();
            label1 = new Label();
            label2 = new Label();
            btnAdd = new Button();
            btnDelete = new Button();
            btnBaseFile = new Button();
            btnOutputFolder = new Button();
            txtNewIdentifier = new TextBox();
            label3 = new Label();
            txtOutputFile = new TextBox();
            btnFork = new Button();
            txtProgress = new TextBox();
            SuspendLayout();
            // 
            // chkOverwrite
            // 
            chkOverwrite.AutoSize = true;
            chkOverwrite.Location = new Point(264, 331);
            chkOverwrite.Name = "chkOverwrite";
            chkOverwrite.Size = new Size(439, 45);
            chkOverwrite.TabIndex = 0;
            chkOverwrite.Text = "Overwrite existing output file";
            chkOverwrite.UseVisualStyleBackColor = true;
            chkOverwrite.CheckedChanged += chkOverwrite_CheckedChanged;
            // 
            // txtBaseFile
            // 
            txtBaseFile.Location = new Point(280, 52);
            txtBaseFile.Name = "txtBaseFile";
            txtBaseFile.Size = new Size(756, 47);
            txtBaseFile.TabIndex = 1;
            txtBaseFile.TextChanged += txtBaseFile_TextChanged;
            // 
            // lstIdentifiers
            // 
            lstIdentifiers.Anchor = AnchorStyles.Bottom | AnchorStyles.Left | AnchorStyles.Right;
            lstIdentifiers.FormattingEnabled = true;
            lstIdentifiers.ItemHeight = 41;
            lstIdentifiers.Location = new Point(32, 445);
            lstIdentifiers.Name = "lstIdentifiers";
            lstIdentifiers.Size = new Size(448, 291);
            lstIdentifiers.TabIndex = 2;
            // 
            // openFileDialog1
            // 
            openFileDialog1.FileName = "openFileDialog1";
            // 
            // txtOutputFolder
            // 
            txtOutputFolder.Location = new Point(280, 140);
            txtOutputFolder.Name = "txtOutputFolder";
            txtOutputFolder.Size = new Size(756, 47);
            txtOutputFolder.TabIndex = 3;
            txtOutputFolder.TextChanged += txtOutputFolder_TextChanged;
            // 
            // label1
            // 
            label1.AutoSize = true;
            label1.Location = new Point(25, 52);
            label1.Name = "label1";
            label1.Size = new Size(139, 41);
            label1.TabIndex = 4;
            label1.Text = "Base File:";
            // 
            // label2
            // 
            label2.AutoSize = true;
            label2.Location = new Point(25, 143);
            label2.Name = "label2";
            label2.Size = new Size(249, 41);
            label2.TabIndex = 5;
            label2.Text = "Output Directory:";
            // 
            // btnAdd
            // 
            btnAdd.Anchor = AnchorStyles.Bottom | AnchorStyles.Left | AnchorStyles.Right;
            btnAdd.Location = new Point(782, 445);
            btnAdd.Name = "btnAdd";
            btnAdd.Size = new Size(254, 106);
            btnAdd.TabIndex = 6;
            btnAdd.Text = "Add new identifier";
            btnAdd.UseVisualStyleBackColor = true;
            btnAdd.Click += btnAdd_Click;
            // 
            // btnDelete
            // 
            btnDelete.Anchor = AnchorStyles.Bottom | AnchorStyles.Left | AnchorStyles.Right;
            btnDelete.Location = new Point(505, 445);
            btnDelete.Name = "btnDelete";
            btnDelete.Size = new Size(254, 106);
            btnDelete.TabIndex = 7;
            btnDelete.Text = "Delete Identifier";
            btnDelete.UseVisualStyleBackColor = true;
            btnDelete.Click += btnDelete_Click;
            // 
            // btnBaseFile
            // 
            btnBaseFile.Location = new Point(1058, 46);
            btnBaseFile.Name = "btnBaseFile";
            btnBaseFile.Size = new Size(345, 58);
            btnBaseFile.TabIndex = 8;
            btnBaseFile.Text = "Select Base File";
            btnBaseFile.UseVisualStyleBackColor = true;
            btnBaseFile.Click += btnBaseFile_Click;
            // 
            // btnOutputFolder
            // 
            btnOutputFolder.Location = new Point(1058, 134);
            btnOutputFolder.Name = "btnOutputFolder";
            btnOutputFolder.Size = new Size(345, 58);
            btnOutputFolder.TabIndex = 9;
            btnOutputFolder.Text = "Select Output Folder";
            btnOutputFolder.UseVisualStyleBackColor = true;
            btnOutputFolder.Click += btnOutputFolder_Click;
            // 
            // txtNewIdentifier
            // 
            txtNewIdentifier.Anchor = AnchorStyles.Bottom | AnchorStyles.Left | AnchorStyles.Right;
            txtNewIdentifier.Location = new Point(1058, 475);
            txtNewIdentifier.Name = "txtNewIdentifier";
            txtNewIdentifier.Size = new Size(345, 47);
            txtNewIdentifier.TabIndex = 10;
            txtNewIdentifier.Text = "{}";
            // 
            // label3
            // 
            label3.AutoSize = true;
            label3.Location = new Point(25, 232);
            label3.Name = "label3";
            label3.Size = new Size(173, 41);
            label3.TabIndex = 12;
            label3.Text = "Output File:";
            // 
            // txtOutputFile
            // 
            txtOutputFile.Location = new Point(280, 229);
            txtOutputFile.Name = "txtOutputFile";
            txtOutputFile.Size = new Size(756, 47);
            txtOutputFile.TabIndex = 11;
            txtOutputFile.TextChanged += txtOutputFile_TextChanged;
            // 
            // btnFork
            // 
            btnFork.Location = new Point(1058, 232);
            btnFork.Name = "btnFork";
            btnFork.Size = new Size(345, 192);
            btnFork.TabIndex = 13;
            btnFork.Text = "Fork!";
            btnFork.UseVisualStyleBackColor = true;
            btnFork.Click += btnFork_Click;
            // 
            // txtProgress
            // 
            txtProgress.Location = new Point(509, 569);
            txtProgress.Multiline = true;
            txtProgress.Name = "txtProgress";
            txtProgress.ScrollBars = ScrollBars.Both;
            txtProgress.Size = new Size(894, 167);
            txtProgress.TabIndex = 14;
            // 
            // Form1
            // 
            AutoScaleDimensions = new SizeF(17F, 41F);
            AutoScaleMode = AutoScaleMode.Font;
            ClientSize = new Size(1429, 772);
            Controls.Add(txtProgress);
            Controls.Add(btnFork);
            Controls.Add(label3);
            Controls.Add(txtOutputFile);
            Controls.Add(txtNewIdentifier);
            Controls.Add(btnOutputFolder);
            Controls.Add(btnBaseFile);
            Controls.Add(btnDelete);
            Controls.Add(btnAdd);
            Controls.Add(label2);
            Controls.Add(label1);
            Controls.Add(txtOutputFolder);
            Controls.Add(lstIdentifiers);
            Controls.Add(txtBaseFile);
            Controls.Add(chkOverwrite);
            Name = "Form1";
            Text = "ForkPowerPointDeck";
            Load += Form1_Load;
            ResumeLayout(false);
            PerformLayout();
        }

        #endregion

        private CheckBox chkOverwrite;
        private TextBox txtBaseFile;
        private ListBox lstIdentifiers;
        private OpenFileDialog openFileDialog1;
        private TextBox txtOutputFolder;
        private Label label1;
        private Label label2;
        private Button btnAdd;
        private Button btnDelete;
        private Button btnBaseFile;
        private Button btnOutputFolder;
        private TextBox txtNewIdentifier;
        private Label label3;
        private TextBox txtOutputFile;
        private Button btnFork;
        private TextBox txtProgress;
    }
}
