This blueprint installs forked-daapd with a current version of ffmpeg.
As it compiles ffmepg from sources the initialisation takes a while.

`forked-daapd` needs to know the location of your iTunes Library. Add `a path:`
section to your `config.yaml` with the value `itunes` to indicate the path to
your iTunes Library relative to the `media` dataset.

```
  ...
  dataset:
     ...
    # Media library dataset
    media: tank/media
    paths:
      itunes: Music/iTunes Music
      ...
```
