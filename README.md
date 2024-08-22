<img align="right" src="bluejay.svg" alt="Bluejay" width="250">

# Bluejay

[![GitHub release (latest by date)](https://img.shields.io/github/downloads/bird-sanctuary/bluejay/latest/total?style=for-the-badge)](https://github.com/bird-sanctuary/bluejay/releases/latest)
[![Discord](https://img.shields.io/discord/822952715944460368?color=7289da&label=Discord&logo=discord&logoColor=white&style=for-the-badge)](https://discord.gg/ddyzguPB5t)

Digital ESC firmware for controlling brushless motors in multirotors.

> Based on [BLHeli_S](https://github.com/bitdump/BLHeli) revision 16.7

Bluejay aims to be an open source successor to BLHeli_S adding several improvements to ESCs with Busy Bee MCUs.

## Current Features

- Digital signal protocol: DShot 300 and 600
- Bidirectional DShot: RPM telemetry and [extended DSHOT telemetry](https://github.com/bird-sanctuary/extended-dshot-telemetry)
- Selectable PWM frequency: 24, 48 and 96 kHz
- Power configuration: Startup power and RPM protection
- High performance: Low commutation interference
- Smoother throttle to PWM conversion
- User configurable startup tunes :musical_note:
- Numerous optimizations and bug fixes

See the projects [release page](https://github.com/bird-sanctuary/bluejay/releases) to understand what changed between versions.

## Supported Platforms
- SiLabs EFM8 BB21
- SiLabs EFM8 BB51

### Deprecated Platforms
The `SiLabs EFM8 BB10` - commonly also known as L layout - has been deprecated. The last official release is [0.18.1](https://github.com/bird-sanctuary/bluejay/releases/tag/v0.18.1). The BB10 has it's limitations in comparison to the BB21 and BB51. Not many of those seem to be around anymore and the team does not have a single one for testing, thus decided to drop support.

> You will still be able to manually build for it, but we can not guarantee compatibility and do not want to suffer from it's limitations during further development.

## Flashing ESCs
Bluejay firmware can be flashed to BLHeli_S compatible ESCs and configured using the following configurator tools:

- [ESC Configurator](https://esc-configurator.com/) (PWA)
- [Bluejay Configurator](https://github.com/mathiasvr/bluejay-configurator/releases) (Standalone)

You can also do it manually by downloading the [release binaries](https://github.com/bird-sanctuary/bluejay/wiki/Release-binaries).

## Documentation
See the [wiki](https://github.com/bird-sanctuary/bluejay/wiki) for useful information. A very detailed documentation with flow charts is [available too](https://github.com/bird-sanctuary/bluejay-documentation).

## Ancestry
This is a fork of the original [Bluejay](https://github.com/mathiasvr/bluejay) project. The team has decided to detach this fork from the orignal project in order to have all github features to their disposal.

The decision to keep the name was made in order to honour the orignal project and the hope that the original developer will join us here, once he decides to make a comeback.

## Supporters
This project is run by a small core team devoting a lot of their spare time and money into pushing this project forward. Development of ESC firmware is time consuming and mistakes are expensive: Motors, ESCs and Flight-Controllers tend to break from time to time, especially if pushing the limits.

We do not take monetary donations, but we have a [donation Wiki page](https://github.com/bird-sanctuary/bluejay/wiki/Donations) where you can see which hardware we are currently looking for - if you want to help out, consider getting in touch with us and buying us some hardware we need.

### Community
A big shout out goes out to the following members of the community for donating hardware - listed by their real name, Discord handle or github username if known:

* 406FPV - for donating a F722 based flight-controller, motors and a whole 1105 based micro quad
* belrik - for donating a set of 2207 motors
* Ced_51 - for dontaing multiple sets of different motors (2207, 2306)
* geordil - for donating a F722 based flight-controller
* Miguel Juncal - for donating a 5" quad and a set of Sunnysky motors
* RabbitAmbulance - for donating a set of 2207 motors

### Manufacturers
We are in a very lucky position to have manufacturers who keep helping us out continuously and who deserve a shoutout:

* [BetaFPV](https://betafpv.com/) - for providing us with dev boards for BB51 MCUs, AIO Flight-controllers, Motors and Whoops
* [Happymodel](https://www.happymodel.cn/) - for providing us with Whoops
* [Skystars](https://skystars-rc.com/) - for providing us with flight-controllers and ESCs
* [T-Motor](https://tmotorhobby.com/) - for providing us with an AIO flight-controller
* [TuneRC](https://www.tunerc.com/) - for providing us with AIO flight-controllers
* [weBLEEDfpv](https://webleedfpv.com/) - for a set of "Gore V2" motors
* [HAKRC](https://www.hakrc.com/) - for providing us with ESCs

## Contribute
Any help you can provide is greatly appreciated!

If you have problems, suggestions or other feedback you can open an [issue](https://github.com/bird-sanctuary/bluejay/issues).

You can also join our [Discord server](https://discord.gg/ddyzguPB5t) to ask questions and to discuss Bluejay!

### Pull Requests
If you have fixed an issue or added a functionality, please feel free to submit a pull request. Direct your PRs against the develop branch of this repository.

### Build
Please see the [wiki](https://github.com/bird-sanctuary/bluejay/wiki/Development#building-from-source) for instructions on how to build Bluejay from source.
