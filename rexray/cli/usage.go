package cli

import (
	"fmt"
	"io/ioutil"
	rx "regexp"
	"strings"
	"text/template"

	log "github.com/Sirupsen/logrus"
	"github.com/emccode/rexray/util"
	"github.com/spf13/cobra"
	flag "github.com/spf13/pflag"
)

func (c *CLI) initUsageTemplates() {

	var ut string
	utPath := fmt.Sprintf("%s/.rexray/usage.template", util.HomeDir())
	log.WithField("path", utPath).Debug("usage template path")

	if util.FileExists(utPath) {
		dat, err := ioutil.ReadFile(utPath)
		if err != nil {
			panic(err)
		}
		log.WithField("source", utPath).Debug("loaded usage template")
		ut = string(dat)
	} else {
		log.WithField("source", "UsageTemplate").Debug("loaded usage template")
		ut = usageTemplate
	}

	c.c.SetUsageTemplate(ut)
	c.c.SetHelpTemplate(ut)

	cobra.AddTemplateFuncs(template.FuncMap{
		"af":    c.additionalFlags,
		"afs":   c.additionalFlagSets,
		"hf":    hasFlags,
		"lf":    c.localFlags,
		"gf":    c.globalFlags,
		"df":    c.driverFlags,
		"ihf":   isHelpFlag,
		"ivf":   isVerboseFlag,
		"saf":   c.sansAdditionalFlags,
		"cmds":  commands,
		"rtrim": rtrim,
	})
}

func (c *CLI) localFlags(cmd *cobra.Command) *flag.FlagSet {

	fs := &flag.FlagSet{}

	if cmd.HasParent() {
		cmd.LocalFlags().VisitAll(func(f *flag.Flag) {
			if f.Name != "help" {
				fs.AddFlag(f)
			}
		})
	} else {
		cmd.LocalFlags().VisitAll(func(f *flag.Flag) {
			if cmd.PersistentFlags().Lookup(f.Name) == nil {
				fs.AddFlag(f)
			}
		})
	}

	return c.sansAdditionalFlags(fs)
}

func (c *CLI) globalFlags(cmd *cobra.Command) *flag.FlagSet {
	fs := &flag.FlagSet{}
	if cmd.HasParent() {
		fs.AddFlagSet(cmd.InheritedFlags())
		if fs.Lookup("help") == nil && cmd.Flag("help") != nil {
			fs.AddFlag(cmd.Flag("help"))
		}
	} else {
		fs.AddFlagSet(cmd.PersistentFlags())
	}
	return c.sansDriverFlags(c.sansAdditionalFlags(fs))
}

func (c *CLI) driverFlags() *flag.FlagSet {
	return c.r.Config.FlagSets()["Driver Flags"]
}

func (c *CLI) sansAdditionalFlags(flags *flag.FlagSet) *flag.FlagSet {
	fs := &flag.FlagSet{}
	flags.VisitAll(func(f *flag.Flag) {
		if c.additionalFlags().Lookup(f.Name) == nil {
			fs.AddFlag(f)
		}
	})
	return fs
}

func (c *CLI) sansDriverFlags(flags *flag.FlagSet) *flag.FlagSet {
	fs := &flag.FlagSet{}
	flags.VisitAll(func(f *flag.Flag) {
		if c.driverFlags().Lookup(f.Name) == nil {
			fs.AddFlag(f)
		}
	})
	return fs
}

func hasFlags(flags *flag.FlagSet) bool {
	return flags != nil && flags.HasFlags()
}

func (c *CLI) additionalFlags() *flag.FlagSet {
	af := &flag.FlagSet{}
	for _, fs := range c.additionalFlagSets() {
		af.AddFlagSet(fs)
	}
	return af
}

func (c *CLI) additionalFlagSets() map[string]*flag.FlagSet {
	afs := map[string]*flag.FlagSet{}
	for fsn, fs := range c.r.Config.FlagSets() {
		if fsn == "Global Flags" || fsn == "Driver Flags" {
			continue
		}
		afs[fsn] = fs
	}
	return afs
}

func isHelpFlag(cmd *cobra.Command) bool {
	v, e := cmd.Flags().GetBool("help")
	if e != nil {
		panic(e)
	}
	return v
}

func isVerboseFlag(cmd *cobra.Command) bool {
	v, e := cmd.Flags().GetBool("verbose")
	if e != nil {
		panic(e)
	}
	return v
}

func commands(cmd *cobra.Command) []*cobra.Command {
	if cmd.HasParent() {
		return cmd.Commands()
	}

	cArr := []*cobra.Command{}
	for _, c := range cmd.Commands() {
		if m, _ := rx.MatchString("((re)?start)|stop|status|((un)?install)", c.Name()); !m {
			cArr = append(cArr, c)
		}
	}
	return cArr
}

func rtrim(text string) string {
	return strings.TrimRight(text, " \n")
}

const usageTemplate = `{{$cmd := .}}{{with or .Long .Short }}{{. | trim}}{{end}}

Usage: {{if .Runnable}}
  {{.UseLine}}{{if .HasFlags}} [flags]{{end}}{{end}}{{if .HasSubCommands}}
  {{ .CommandPath}} [command]{{end}}{{if gt .Aliases 0}}

Aliases:
  {{.NameAndAliases | rtrim}}{{end}}{{if .HasExample}}

Examples:
{{.Example | rtrim}}{{end}}{{ if .HasAvailableSubCommands}}

Available Commands: {{range cmds $cmd}}{{if (not .IsHelpCommand)}}
  {{rpad .Name .NamePadding }} {{.Short | rtrim}}{{end}}{{end}}{{end}}{{$lf := lf $cmd}}{{if hf $lf}}

Flags:
{{$lf.FlagUsages | rtrim}}{{end}}{{$gf := gf $cmd}}{{if hf $gf}}

Global Flags:
{{$gf.FlagUsages | rtrim}}{{end}}{{if ivf $cmd}}{{$df := df}}{{if hf $df}}

Driver Flags:
{{$df.FlagUsages | rtrim}}{{end}}
{{range $fn, $fs := afs}}
{{$fn}}
{{$fs.FlagUsages | rtrim}}
{{end}}{{end}}{{if .HasHelpSubCommands}}

Additional help topics: {{range .Commands}}{{if .IsHelpCommand}}
  {{rpad .CommandPath .CommandPathPadding}} {{.Short | rtrim}}{{end}}}{{end}}{{end}}{{if .HasSubCommands}}

Use "{{.CommandPath}} [command] --help" for more information about a command.{{end}}

`
