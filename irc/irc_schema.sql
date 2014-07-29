#
# Encoding: Unicode (UTF-8)
#


CREATE TABLE `irc_channel` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `name` varchar(128) DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=3 DEFAULT CHARSET=utf8;


CREATE TABLE `irc_user` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `shortname` varchar(128) DEFAULT NULL,
  `longname` varchar(128) DEFAULT NULL,
  `realname` varchar(128) DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=13 DEFAULT CHARSET=utf8;


CREATE TABLE `irc_log` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `irc_channel_id` int(11) DEFAULT NULL,
  `irc_user_id` int(11) DEFAULT NULL,
  `irc_command` varchar(128) DEFAULT NULL,
  `message` varchar(2048) DEFAULT NULL,
  `logged_at` datetime DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `irc_channel_id` (`irc_channel_id`),
  KEY `irc_user_id` (`irc_user_id`),
  CONSTRAINT `irc_log_ibfk_2` FOREIGN KEY (`irc_user_id`) REFERENCES `irc_user` (`id`),
  CONSTRAINT `irc_log_ibfk_1` FOREIGN KEY (`irc_channel_id`) REFERENCES `irc_channel` (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=45 DEFAULT CHARSET=utf8;




