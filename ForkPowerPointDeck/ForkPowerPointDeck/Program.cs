// See https://aka.ms/new-console-template for more information

//read in the base presentation
using ForkPowerPointDeck;

string _baseFile = string.Empty;
string _outputFile = string.Empty;
string _slidesWithIdentifierToKeep = string.Empty;
bool _overwriteOutput = false;
bool _removeCameos = false;
bool _removeComments = true;
bool _removeEmptySections = true;

//make sure we have all 3 necessary inputs: baseFile(b), outputFile(o), identifierToKeep(i)
//and then the optional one for overwrite(w)
#if DEBUG
    Console.WriteLine("arg count = " + args.Count());
#endif

if (args.Count() < 3)
{
    Console.WriteLine("Missing required command line parameter!");
    Console.WriteLine("-b{baseFile without .pptx}");
    Console.WriteLine("-o{outputFile without .pptx}");
    Console.WriteLine("-i{identifier to keep}");
    Environment.Exit(-1);
}

//process the command line args
for (int i = 0; i < args.Length; i++)
{
    switch (args[i].Substring(1,1))
    {
        case "b":
            _baseFile = args[i].Substring(2) + ".pptx";

#if DEBUG
            Console.WriteLine("baseFile = " +  _baseFile);
#endif
            //if the input file doesn't exist, exit
            if (!File.Exists(_baseFile))
            {
                Console.WriteLine("Base file doesn't exist!");
                Environment.Exit(-1);
            }

            break;
        case "o":
            _outputFile = args[i].Substring(2) + ".pptx";
            break;
        case "i":
            _slidesWithIdentifierToKeep = args[i].Substring(2);
            Console.WriteLine("identifier to keep  = " + _slidesWithIdentifierToKeep);
            break;
        case "w":
            Console.WriteLine("will overwrite output file");
            _overwriteOutput = true;
            break;
        case "c":
            _removeCameos = true;
            break;
        case "a":
            _removeComments = false;
            break;
        case "s":
            _removeEmptySections = false;
            break;
        default:
            // Code to handle unknown argument
            Console.WriteLine("Bad input parameter");
            Environment.Exit(-1);
            break;
    }
}

if (string.IsNullOrEmpty(_slidesWithIdentifierToKeep))
{
    Console.WriteLine("Slides to keep identifier not specified.");
    Environment.Exit(-1);
}

//remove the Cameos behavior
switch (_removeCameos)
{
    case true:
        Console.WriteLine("Will remove cameos");
        break;
    case false:
        Console.WriteLine("Will NOT remove cameos");
        break;
}

//report the comments behavior
switch (_removeComments)
{
    case false:
        Console.WriteLine("Will NOT remove comments by all authors");
        break;
    case true:
        Console.WriteLine("Will remove comments by all authors");
        break;
}

//remote the empty sections behavior
switch (_removeEmptySections)
{
    case false:
        Console.WriteLine("Will NOT remove empty sections");
        break;
    case true:
        Console.WriteLine("Will remove empty sections");
        break;
}


if (!PresentationManagement.ForkPresentation(_baseFile, _outputFile, _slidesWithIdentifierToKeep, _overwriteOutput, _removeCameos, _removeComments, _removeEmptySections))
{
    Console.WriteLine("Error forking presentation");
    Environment.Exit(-1);
}