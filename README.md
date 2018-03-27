# Gerrit-CLI

#### A convenient tool which wraps several commands supported by Gerrit via its internal SSH daemon.

## Introduction

- For purpose of leveraging Gerrit command line tools, this project wraps common Gerrit commands with a single Shell script named **gerrit-cli.sh**.

## Configuration

### 1. Set up config file **config.json**

- In order to get the following required three pieces of information for script **gerrit-cli.sh**, you need to create a JSON-formatted config file named **config.json** under path **$HOME/.gerrit**.
  1) Site of your Gerrit server
  2) SSH Port of your Gerrit server
  3) Name of your account of the Gerrit server

> NOTE:
> 1. Creates path **$HOME/.gerrit** if it does not exit.

- Here is an example of config file **config.json**.
```json
{
    "host": "gerritro.sdesigns.com",
    "port": 29418,
    "user": "blankliu"
}
```

> NOTE:
> 1. Replaces values for those three fields with your own information.

### 2. Put script **gerrit-cli.sh** into System path

- In order to use script **gerrit-cli.sh** anywhere within your Shell terminal, you need to put it into the System path.
```shell
mkdir $HOME/.bin
curl -Lo $HOME/.bin/gerrit-cli.sh https://raw.githubusercontent.com/blankliu/Gerrit-CLI/master/gerrit-cli.sh
chmod a+x $HOME/.bin/gerrit-cli.sh
sudo ln -sf $HOME/.bin/gerrit-cli.sh /usr/bin/gerrit-cli.sh
```

## How to Extend Script gerrit-cli.sh

#### Supposes you want to wrap Gerrit command '*set-head*', here are the steps to implement it.

- Appends a new item into array **CMD_USAGE_MAPPING** within function **__init_command_context**

```shell
# Uses string 'set-head' as index
# String '__print_usage_of_set_head' is the name of a new Shell function
CMD_USAGE_MAPPING["set-head"]="__print_usage_of_set_head"
```

- Appends a new item into array **CMD_OPTION_MAPPING** within function **__init_command_context**

```shell
# Uses string 'set-head' as index

# Creates options according to official document of Gerrit command 'set-head'
# Refers to usage of Shell command 'getopt' for how options are analyzed by 'getopt'
CMD_OPTION_MAPPING["set-head"]="p:h: -l project:head:"
```

- Appends a new item into array **CMD_FUNCTION_MAPPING** within function **__init_command_context**

```shell
# Uses string 'set-head' as index
# String '__set_head' is the name of a new Shell function
CMD_FUNCTION_MAPPING["set-head"]="__set_head"
```

- Implements two new Shell functions **__print_usage_of_set_head** and **__set_head**
> NOTE:
> 1. Shell function **__print_usage_of_set_head**
>    * It shows how to use sub-command 'set-head' with script **gerrit-cli.sh**.
>    * You could refer to function **__print_usage_of_create_branch** for implementation.
> 2. Shell Function **__set_head**
>    * It implements the work of setting HEAD reference for a project.
>    * You could refer to function **__create_branch** for implementation.

- Complements information of sub-command 'set-head' within function **__print_cli_usage**

## How to Use

### 1. Show which Gerrit commands are wrapped by script **gerrit-cli.sh**

```shell
gerrit-cli.sh --help
```

### 2. Show usage of a Gerrit command using script **gerrit-cli.sh**

- Takes Gerrit command '*create-branch*' as an example, there are two ways to show its usage

```shell
gerrit-cli.sh help create-branch
gerrit-cli.sh create-branch --help
```

## References

- Google Gerrit Project: [Click Here](https://www.gerritcodereview.com)
- Official document of Gerrit (V2.14.6) command line tools: [Click Here](https://gerrit-documentation.storage.googleapis.com/Documentation/2.14.6/cmd-index.html)
